"""
Reads the QuestieDB addon's Forever database (Interface/AddOns/QuestieDB/QuestieDB_Forever.toc).

QuestieDB "baked mode" keeps every quest, NPC and object as CBOR rows in the TOC's metadata lines:
  ## X-Quest-<id>-S: base64 CBOR map {field index: scalar value, p = bit mask of present table fields}
  ## X-Quest-<id>-<field>: base64 CBOR table field
  ## X-<Entity>-IDS: ~N~ header, then -1 .. -N parts (base64, zlib) with the ID list
Field numbers come from QuestieDB/src/meta/{quest,npc,object}Meta.lua.
This is a local, compliant addon file: no web access.

load() returns {"quests": {id: {...}}, "npcs": {id: {...}}, "objects": {id: {...}}} with named fields.
"""

import base64
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from auctionator import cbor  # noqa: E402

TOC_GLOB = "/Applications/World of Warcraft/_*_/Interface/AddOns/QuestieDB/QuestieDB_Forever.toc"

QUEST_FIELDS = {1: "name", 2: "startedBy", 3: "finishedBy", 4: "requiredLevel", 5: "questLevel",
                6: "requiredRaces", 7: "requiredClasses", 8: "objectivesText", 9: "triggerEnd", 10: "objectives",
                11: "sourceItemId", 12: "preQuestGroup", 13: "preQuestSingle", 14: "childQuests",
                16: "exclusiveTo", 17: "zoneOrSort", 18: "requiredSkill", 22: "nextQuestInChain",
                23: "questFlags", 24: "specialFlags", 25: "parentQuest", 27: "breadcrumbForQuestId",
                28: "breadcrumbs", 32: "requiredMaxLevel"}
NPC_FIELDS = {1: "name", 4: "minLevel", 5: "maxLevel", 6: "rank", 7: "spawns", 9: "zoneID",
              10: "questStarts", 11: "questEnds", 13: "friendlyToFaction", 14: "subName"}
OBJECT_FIELDS = {1: "name", 2: "questStarts", 3: "questEnds", 4: "spawns", 5: "zoneID"}
ITEM_FIELDS = {1: "name", 2: "npcDrops", 3: "objectDrops", 5: "startQuest"}


def toc_path():
    paths = sorted(glob.glob(TOC_GLOB))
    return paths[-1] if paths else None


def read_meta(path):
    meta = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("## X-") and ": " in line:
                key, value = line[3:].rstrip("\n").split(": ", 1)
                meta[key] = value
    return meta


def stored(meta, key):
    value = meta.get(key)
    if value and value.startswith("~") and value.endswith("~"):
        return "".join(meta[f"{key}-{i}"] for i in range(1, int(value[1:-1]) + 1))
    return value


def decode(value):
    return cbor(base64.b64decode(value))[0]


def fix_keys(value):
    """CBOR maps come back with string keys; turn numeric ones back into ints, recursively."""
    if isinstance(value, dict):
        return {(int(k) if k.lstrip("-").isdigit() else k): fix_keys(v) for k, v in value.items()}
    if isinstance(value, list):
        return [fix_keys(v) for v in value]
    return value


def entities(meta, prefix, fields):
    ids = set()
    for key in meta:
        if key.startswith(prefix) and key.endswith("-S"):
            ids.add(int(key[len(prefix):-2]))
    out = {}
    for eid in ids:
        row = fix_keys(decode(meta[f"{prefix}{eid}-S"]))
        entry = {}
        for idx, name in fields.items():
            if idx in row:
                entry[name] = row[idx]
            else:
                raw = stored(meta, f"{prefix}{eid}-{idx}")
                if raw:
                    entry[name] = fix_keys(decode(raw))
        out[eid] = entry
    return out


def load(path=None):
    path = path or toc_path()
    if not path:
        return None
    meta = read_meta(path)
    return {
        "quests": entities(meta, "X-Quest-", QUEST_FIELDS),
        "npcs": entities(meta, "X-Npc-", NPC_FIELDS),
        "objects": entities(meta, "X-Object-", OBJECT_FIELDS),
        "items": entities(meta, "X-Item-", ITEM_FIELDS),
    }


if __name__ == "__main__":
    db = load()
    if not db:
        sys.exit("QuestieDB_Forever.toc not found")
    print({k: len(v) for k, v in db.items()})
    for qid in (788, 97279, 91899):
        print(qid, json.dumps(db["quests"].get(qid), default=str)[:600])
    print(json.dumps(db["npcs"].get(3143), default=str)[:400])
