#!/usr/bin/env python3
"""
Long-term history in personal/history.sqlite.
The addon keeps only the last 60 price snapshots per item; every sync copies new data here
so nothing is lost. Plain SQL only, so a later move to PostgreSQL stays easy.
"""

import os
import json
import time
import sqlite3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(ROOT, 'personal', 'history.sqlite')  # your characters' history: personal, not in git

SCHEMA = """
CREATE TABLE IF NOT EXISTS price_snapshots (
    scope TEXT NOT NULL,
    item TEXT NOT NULL,
    t INTEGER NOT NULL,
    min_price INTEGER NOT NULL,
    median_price INTEGER,
    quantity INTEGER,
    PRIMARY KEY (scope, item, t)
);
CREATE TABLE IF NOT EXISTS trainer_recipes (
    client TEXT NOT NULL,
    profession TEXT NOT NULL,
    recipe TEXT NOT NULL,
    skill INTEGER,
    level INTEGER,
    cost INTEGER,
    seen INTEGER,
    PRIMARY KEY (client, profession, recipe)
);
CREATE TABLE IF NOT EXISTS character_snapshots (
    char_key TEXT NOT NULL,
    t INTEGER NOT NULL,
    level INTEGER,
    money INTEGER,
    professions TEXT,
    PRIMARY KEY (char_key, t)
);
CREATE TABLE IF NOT EXISTS vendor_recipes (
    client TEXT NOT NULL,
    recipe TEXT NOT NULL,
    item TEXT,
    profession TEXT,
    skill INTEGER,
    vendor TEXT NOT NULL,
    zone TEXT,
    subzone TEXT,
    price INTEGER,
    limited INTEGER,
    seen INTEGER,
    PRIMARY KEY (client, recipe, vendor)
);
CREATE TABLE IF NOT EXISTS known_recipes (
    char_key TEXT NOT NULL,
    profession TEXT NOT NULL,
    recipe TEXT NOT NULL,
    difficulty TEXT,
    reagents TEXT,
    scanned INTEGER,
    PRIMARY KEY (char_key, profession, recipe)
);
"""


# Keys carry the game client ("classic_beta|...") so beta and live data never mix.
# Rows from before that change were all beta.
LEGACY_CLIENT = 'classic_beta'


def _migrate(conn):
    cols = [r[1] for r in conn.execute("PRAGMA table_info(trainer_recipes)")]
    if cols and 'client' not in cols:
        conn.execute("ALTER TABLE trainer_recipes RENAME TO trainer_recipes_old")
        conn.executescript(SCHEMA)
        conn.execute("INSERT INTO trainer_recipes SELECT ?, profession, recipe, skill, level, cost, seen FROM trainer_recipes_old",
                     (LEGACY_CLIENT,))
        conn.execute("DROP TABLE trainer_recipes_old")
    conn.execute("UPDATE price_snapshots SET scope = ? || '|' || scope WHERE scope NOT LIKE '%|%'", (LEGACY_CLIENT,))
    conn.execute("UPDATE character_snapshots SET char_key = ? || '|' || char_key WHERE char_key NOT LIKE '%|%'", (LEGACY_CLIENT,))
    conn.execute("UPDATE known_recipes SET char_key = ? || '|' || char_key WHERE char_key NOT LIKE '%|%'", (LEGACY_CLIENT,))
    conn.commit()


BACKUP_DIR = os.path.join(ROOT, 'personal', 'backups')
BACKUP_KEEP = 7


def backup():
    """One safe copy per day (SQLite's online backup, so it is consistent), keeping the newest BACKUP_KEEP."""
    if not os.path.exists(DB_PATH):
        return None
    os.makedirs(BACKUP_DIR, exist_ok=True)
    target = os.path.join(BACKUP_DIR, f"history-{time.strftime('%Y-%m-%d')}.sqlite")
    src = sqlite3.connect(DB_PATH)
    dst = sqlite3.connect(target)
    with dst:
        src.backup(dst)
    src.close()
    dst.close()
    copies = sorted(f for f in os.listdir(BACKUP_DIR) if f.startswith('history-') and f.endswith('.sqlite'))
    for old in copies[:-BACKUP_KEEP]:
        os.remove(os.path.join(BACKUP_DIR, old))
    return target


def connect():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript(SCHEMA)
    _migrate(conn)
    return conn


def ingest(conn, prices, trainers, characters, vendors=None):
    """prices: "client|scope" -> item -> [snapshot]; trainers: client -> profession -> recipe -> info;
    characters: list of dicts with char_key, updated_t, level, money, professions, recipes."""
    cur = conn.cursor()
    new_prices = 0
    for scope, items in prices.items():
        for item, history in items.items():
            for h in history:
                cur.execute(
                    "INSERT OR IGNORE INTO price_snapshots VALUES (?, ?, ?, ?, ?, ?)",
                    (scope, item, h.get('t'), h.get('min'), h.get('med'), h.get('qty')))
                new_prices += cur.rowcount

    for client, professions in trainers.items():
        for profession, recipes in professions.items():
            for recipe, info in recipes.items():
                cur.execute(
                    "INSERT OR REPLACE INTO trainer_recipes VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (client, profession, recipe, info.get('skill'), info.get('level'), info.get('cost'), info.get('seen')))

    for client, recipes in (vendors or {}).items():
        for recipe, v in recipes.items():
            for vendor, info in (v.get('vendors') or {}).items():
                cur.execute(
                    "INSERT OR REPLACE INTO vendor_recipes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (client, recipe, v.get('item'), v.get('profession'), v.get('skill'), vendor,
                     info.get('zone'), info.get('subzone'), info.get('price'), info.get('limited'), info.get('seen')))

    for c in characters:
        if c.get('updated_t'):
            cur.execute(
                "INSERT OR IGNORE INTO character_snapshots VALUES (?, ?, ?, ?, ?)",
                (c['char_key'], c['updated_t'], c.get('level'), c.get('money'), json.dumps(c.get('professions') or [])))
        for profession, scan in (c.get('recipes') or {}).items():
            for recipe, r in (scan.get('recipes') or {}).items():
                cur.execute(
                    "INSERT OR REPLACE INTO known_recipes VALUES (?, ?, ?, ?, ?, ?)",
                    (c['char_key'], profession, recipe, r.get('difficulty'), json.dumps(r.get('reagents') or []), scan.get('scanned')))
    conn.commit()
    return new_prices


def replace_daily_prices(conn, prices):
    """prices: "client|scope" -> item -> [snapshot with 'day0', the start of its day]. Auctionator keeps
    one value per item per day that changes during the day, so each day's rows are replaced.
    Returns how many item-days were new or changed."""
    changed = 0
    for scope, items in prices.items():
        for item, history in items.items():
            for h in history:
                lo, hi = h['day0'], h['day0'] + 86400
                old = conn.execute(
                    "SELECT t, min_price, quantity FROM price_snapshots WHERE scope = ? AND item = ? AND t >= ? AND t < ?",
                    (scope, item, lo, hi)).fetchall()
                if old == [(h['t'], h['min'], h.get('qty'))]:
                    continue
                conn.execute("DELETE FROM price_snapshots WHERE scope = ? AND item = ? AND t >= ? AND t < ?",
                             (scope, item, lo, hi))
                conn.execute("INSERT INTO price_snapshots VALUES (?, ?, ?, ?, ?, ?)",
                             (scope, item, h['t'], h['min'], None, h.get('qty')))
                changed += 1
    conn.commit()
    return changed


def export_prices(conn, days=30):
    """scope -> item -> [snapshot] for the last `days` days, oldest first (the shape index.html expects)."""
    since = int(time.time()) - days * 86400
    out = {}
    rows = conn.execute(
        "SELECT scope, item, t, min_price, median_price, quantity FROM price_snapshots WHERE t >= ? ORDER BY scope, item, t",
        (since,))
    for scope, item, t, mn, med, qty in rows:
        out.setdefault(scope, {}).setdefault(item, []).append({'t': t, 'min': mn, 'med': med, 'qty': qty})
    return out


def export_trainers(conn):
    """client -> profession -> recipe -> info."""
    out = {}
    for client, prof, recipe, skill, level, cost, seen in conn.execute(
            "SELECT client, profession, recipe, skill, level, cost, seen FROM trainer_recipes"):
        out.setdefault(client, {}).setdefault(prof, {})[recipe] = {'skill': skill, 'level': level, 'cost': cost, 'seen': seen}
    return out


def export_vendors(conn):
    """client -> recipe -> {item, profession, skill, vendors: [{vendor, zone, subzone, price, limited}]}."""
    out = {}
    for client, recipe, item, prof, skill, vendor, zone, subzone, price, limited, seen in conn.execute(
            "SELECT client, recipe, item, profession, skill, vendor, zone, subzone, price, limited, seen FROM vendor_recipes"):
        entry = out.setdefault(client, {}).setdefault(recipe, {'item': item, 'profession': prof, 'skill': skill, 'vendors': []})
        entry['vendors'].append({'vendor': vendor, 'zone': zone, 'subzone': subzone, 'price': price, 'limited': limited})
    return out


def stats(conn):
    return {table: conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            for table in ('price_snapshots', 'trainer_recipes', 'vendor_recipes', 'character_snapshots', 'known_recipes')}
