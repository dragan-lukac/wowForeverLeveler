"""
Reads Auctionator's price database (WTF/Account/*/SavedVariables/Auctionator.lua).

Auctionator stores each realm as one CBOR blob (C_EncodingUtil.SerializeCBOR) inside a Lua string:
  realm -> itemID (as text) -> {m = last lowest price, h/l = highest/lowest low price per day,
  a = most listed per day}. Days count from 2020-01-01 00:00 local time (Auctionator's SCAN_DAY_0).
It keeps no item names, so our addon saves name -> itemID (WoWForeverLevelerItemIDs) and
Auctionator realm -> price scope (WoWForeverLevelerAuctionRealms).
"""

import re
import struct
import time

SCAN_DAY_0 = time.mktime((2020, 1, 1, 0, 0, 0, 0, 0, -1))
LUA_ESCAPES = {'n': 10, 't': 9, 'r': 13, 'a': 7, 'b': 8, 'f': 12, 'v': 11, '"': 34, "'": 39, '\\': 92, '\n': 10}


def lua_bytes(raw, start):
    """Decodes the Lua string literal whose opening quote is at raw[start]; returns (bytes, end)."""
    out, i = bytearray(), start + 1
    while raw[i] != 0x22:
        if raw[i] != 0x5C:
            out.append(raw[i])
            i += 1
            continue
        nxt = chr(raw[i + 1])
        if nxt.isdigit():
            digits = re.match(rb'\d{1,3}', raw[i + 1:i + 4]).group()
            out.append(int(digits))
            i += 1 + len(digits)
        else:
            out.append(LUA_ESCAPES[nxt])
            i += 2
    return bytes(out), i + 1


def cbor(data, i=0):
    """Minimal CBOR decoder for what WoW writes: ints, strings, arrays, maps, floats, booleans."""
    head = data[i]
    major, info = head >> 5, head & 31
    i += 1
    if info < 24:
        val = info
    else:
        size = {24: 1, 25: 2, 26: 4, 27: 8}[info]
        raw = data[i:i + size]
        i += size
        if major == 7:
            return struct.unpack({2: '>e', 4: '>f', 8: '>d'}[size], raw)[0], i
        val = int.from_bytes(raw, 'big')
    if major == 0:
        return val, i
    if major == 1:
        return -1 - val, i
    if major in (2, 3):
        return data[i:i + val].decode('utf-8', 'replace'), i + val
    if major == 4:
        items = []
        for _ in range(val):
            v, i = cbor(data, i)
            items.append(v)
        return items, i
    if major == 5:
        result = {}
        for _ in range(val):
            k, i = cbor(data, i)
            v, i = cbor(data, i)
            result[str(k)] = v
        return result, i
    if major == 6:
        return cbor(data, i)
    if major == 7:
        return {20: False, 21: True, 22: None, 23: None}[val], i
    raise ValueError(f"Unknown CBOR byte {head:#x} at {i - 1}")


def read_realms(raw):
    """raw: bytes of Auctionator.lua -> {realm: {itemID: priceData}} for every serialized realm."""
    realms = {}
    section = raw.find(b'AUCTIONATOR_PRICE_DATABASE = {')
    if section < 0:
        return realms
    entry = re.compile(rb'\s*\["([^"]+)"\] = ')
    pos = section + len(b'AUCTIONATOR_PRICE_DATABASE = {')
    while True:
        m = entry.match(raw, pos)
        if not m:
            return realms
        pos = m.end()
        if raw[pos] == 0x22:  # a serialized realm
            blob, pos = lua_bytes(raw, pos)
            data = cbor(blob)[0]
            if isinstance(data, dict):
                realms[m.group(1).decode('utf-8')] = data
        else:  # "__dbversion" = 8, or a realm left as a Lua table (not expected at logout)
            if raw[pos] == ord('{'):
                return realms
            pos = raw.index(b'\n', pos)
        if raw[pos:pos + 1] == b',':
            pos += 1


def day_start(day):
    return int(SCAN_DAY_0 + int(day) * 86400)


def last_scan_time(raw):
    m = re.search(rb'\["TimeOfLastBrowseScan"\] = (\d+)', raw)
    return int(m.group(1)) if m else None


def snapshot_time(day, last_scan):
    """The last full scan's time when it fell on this day, else the day's noon."""
    start = day_start(day)
    if last_scan and start <= last_scan < start + 86400:
        return last_scan
    return start + 43200


def snapshots(item, last_scan=None):
    """One snapshot per day, oldest first: the day's price and the most listed that day.
    A past day uses Auctionator's highest low price of that day (h): its lowest low (l) can be a single
    stray listing (Light Leather once showed 9c against 1s 40c). The newest day uses the last seen price."""
    days = sorted(set(item.get('h') or {}) | set(item.get('a') or {}), key=int)
    out = []
    for day in days:
        price = (item.get('h') or {}).get(day) or (item.get('l') or {}).get(day)
        if day == days[-1] and item.get('m'):
            price = item['m']
        if price:
            out.append({'t': snapshot_time(day, last_scan), 'day0': day_start(day), 'min': int(price),
                        'qty': (item.get('a') or {}).get(day)})
    return out


def prices(raw, item_ids, auction_realms, flavor):
    """-> {"flavor|scope": {item name: [snapshot]}}. item_ids: name -> itemID from our addon;
    auction_realms: Auctionator realm -> our scope. Items without a known name are skipped."""
    names = {str(i): name for name, i in item_ids.items()}
    last_scan = last_scan_time(raw)
    out = {}
    for realm, items in read_realms(raw).items():
        scope = auction_realms.get(realm)
        if not scope:
            continue
        book = out.setdefault(f"{flavor}|{scope}", {})
        for item_id, data in items.items():
            name = names.get(item_id)
            if name and isinstance(data, dict):
                history = snapshots(data, last_scan)
                if history:
                    book[name] = history
    return out
