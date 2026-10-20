"""Tests for the sync scripts. Run with: make test"""

import os
import sys
import json
import sqlite3
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'scripts'))

import history_db  # noqa: E402
import build_guide  # noqa: E402
import server  # noqa: E402
from build_roster import parse_saved_variables  # noqa: E402


class SavedVariablesParserTest(unittest.TestCase):
    def test_nested_tables_arrays_and_escapes(self):
        sv = parse_saved_variables('''
WoWForeverLevelerDB = {
["Realm-Name"] = {
["name"] = "Vestac",
["level"] = 18,
["xp"] = -1.5,
["ok"] = true,
["gone"] = nil,
["professions"] = {
{ ["name"] = "Tailoring", ["rank"] = 60, }, -- [1]
{ ["name"] = "Enchanting", ["rank"] = 38, }, -- [2]
},
["title"] = "Arthas' \\"Tears\\"",
},
}
Other = {}
''')
        char = sv['WoWForeverLevelerDB']['Realm-Name']
        self.assertEqual(char['level'], 18)
        self.assertEqual(char['xp'], -1.5)
        self.assertIs(char['ok'], True)
        self.assertIsNone(char['gone'])
        self.assertEqual([p['name'] for p in char['professions']], ['Tailoring', 'Enchanting'])
        self.assertEqual(char['title'], 'Arthas\' "Tears"')
        self.assertIn('Other', sv)


class HistoryDbTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old_path = history_db.DB_PATH
        history_db.DB_PATH = os.path.join(self.tmp.name, 'history.sqlite')

    def tearDown(self):
        history_db.DB_PATH = self.old_path
        self.tmp.cleanup()

    def test_ingest_is_idempotent_and_keeps_clients_apart(self):
        prices = {
            'classic_beta|Realm-Horde': {'Linen Cloth': [{'t': 1, 'min': 10, 'med': 10, 'qty': 5}]},
            'forever|Realm-Horde': {'Linen Cloth': [{'t': 1, 'min': 99, 'med': 99, 'qty': 5}]},
        }
        trainers = {'classic_beta': {'Tailoring': {'Linen Bag': {'skill': 5, 'cost': 90}}}}
        conn = history_db.connect()
        self.assertEqual(history_db.ingest(conn, prices, trainers, []), 2)
        self.assertEqual(history_db.ingest(conn, prices, trainers, []), 0)
        exported = history_db.export_prices(conn, days=100000)
        self.assertEqual(exported['classic_beta|Realm-Horde']['Linen Cloth'][0]['min'], 10)
        self.assertEqual(exported['forever|Realm-Horde']['Linen Cloth'][0]['min'], 99)
        self.assertEqual(history_db.export_trainers(conn), {'classic_beta': {'Tailoring': {'Linen Bag': {'skill': 5, 'level': None, 'cost': 90, 'seen': None}}}})
        conn.close()

    def test_migrates_rows_from_before_client_labels(self):
        conn = sqlite3.connect(history_db.DB_PATH)
        conn.executescript('''
            CREATE TABLE trainer_recipes (profession TEXT, recipe TEXT, skill INTEGER, level INTEGER, cost INTEGER, seen INTEGER,
                                          PRIMARY KEY (profession, recipe));
            INSERT INTO trainer_recipes VALUES ('Tailoring', 'Linen Bag', 5, NULL, 90, 1);
            CREATE TABLE price_snapshots (scope TEXT, item TEXT, t INTEGER, min_price INTEGER, median_price INTEGER, quantity INTEGER,
                                          PRIMARY KEY (scope, item, t));
            INSERT INTO price_snapshots VALUES ('Realm-Horde', 'Linen Cloth', 1, 10, 10, 5);
        ''')
        conn.commit()
        conn.close()
        conn = history_db.connect()
        self.assertEqual(conn.execute('SELECT client FROM trainer_recipes').fetchone()[0], 'classic_beta')
        self.assertEqual(conn.execute('SELECT scope FROM price_snapshots').fetchone()[0], 'classic_beta|Realm-Horde')
        conn.close()

    def test_backup_keeps_the_newest_copies(self):
        history_db.connect().close()
        old_dir = history_db.BACKUP_DIR
        history_db.BACKUP_DIR = os.path.join(self.tmp.name, 'backups')
        try:
            os.makedirs(history_db.BACKUP_DIR)
            for day in range(1, 10):
                open(os.path.join(history_db.BACKUP_DIR, f'history-2020-01-{day:02d}.sqlite'), 'w').close()
            saved = history_db.backup()
            left = sorted(os.listdir(history_db.BACKUP_DIR))
            self.assertEqual(len(left), history_db.BACKUP_KEEP)
            self.assertEqual(os.path.basename(saved), left[-1])
        finally:
            history_db.BACKUP_DIR = old_dir


def cbor_encode(value):
    """Small CBOR encoder for the test data (the inverse of auctionator.cbor)."""
    def head(major, n):
        if n < 24:
            return bytes([major << 5 | n])
        for info, size in ((24, 1), (25, 2), (26, 4)):
            if n < 1 << (8 * size):
                return bytes([major << 5 | info]) + n.to_bytes(size, 'big')
    if isinstance(value, int):
        return head(0, value)
    if isinstance(value, str):
        data = value.encode()
        return head(3, len(data)) + data
    return head(5, len(value)) + b''.join(cbor_encode(k) + cbor_encode(v) for k, v in value.items())


def lua_quote(data):
    """Writes bytes as a Lua string literal the way WoW does: printable bytes as is, others as \\ddd."""
    out = ''.join(chr(b) if 32 <= b < 127 and b not in (34, 92) else '\\%03d' % b for b in data)
    return '"' + out + '"'


class AuctionatorTest(unittest.TestCase):
    def test_reads_prices_by_name_with_one_snapshot_per_day(self):
        import auctionator
        today = '2465'
        realm = {'2589': {'m': 99, 'h': {'2464': 120, today: 110}, 'l': {today: 95}, 'a': {'2464': 50, today: 80}},
                 '9999': {'m': 5, 'h': {today: 5}, 'a': {today: 1}}, 'version': 2}
        scan = auctionator.day_start(today) + 3600
        raw = ('AUCTIONATOR_SAVEDVARS = {\n["TimeOfLastBrowseScan"] = %d,\n}\n'
               'AUCTIONATOR_PRICE_DATABASE = {\n["__dbversion"] = 8,\n["BetaPvP"] = %s,\n["Other"] = %s,\n}\n'
               % (scan, lua_quote(cbor_encode(realm)), lua_quote(cbor_encode({})))).encode('latin1')
        found = auctionator.prices(raw, {'Linen Cloth': 2589}, {'BetaPvP': 'Beta PvP-Horde'}, 'classic_beta')
        history = found['classic_beta|Beta PvP-Horde']['Linen Cloth']
        self.assertEqual([h['min'] for h in history], [120, 99])  # newest day: the last seen price
        self.assertEqual([h['qty'] for h in history], [50, 80])
        self.assertEqual(history[-1]['t'], scan)
        self.assertEqual(history[0]['t'], auctionator.day_start('2464') + 43200)
        self.assertEqual(list(found['classic_beta|Beta PvP-Horde']), ['Linen Cloth'])  # no name: skipped

    def test_daily_prices_replace_the_same_day(self):
        tmp = tempfile.TemporaryDirectory()
        old_path = history_db.DB_PATH
        history_db.DB_PATH = os.path.join(tmp.name, 'history.sqlite')
        try:
            conn = history_db.connect()
            day = {'scope': {'Linen Cloth': [{'t': 1000, 'day0': 0, 'min': 99, 'qty': 5}]}}
            self.assertEqual(history_db.replace_daily_prices(conn, day), 1)
            self.assertEqual(history_db.replace_daily_prices(conn, day), 0)
            later = {'scope': {'Linen Cloth': [{'t': 5000, 'day0': 0, 'min': 80, 'qty': 9}]}}
            self.assertEqual(history_db.replace_daily_prices(conn, later), 1)
            rows = conn.execute('SELECT t, min_price, quantity FROM price_snapshots').fetchall()
            self.assertEqual(rows, [(5000, 80, 9)])
            conn.close()
        finally:
            history_db.DB_PATH = old_path
            tmp.cleanup()


class DungeonAddonsTest(unittest.TestCase):
    def test_keeps_id_keys_and_reads_horde_quests_with_rewards(self):
        import dungeon_addons
        sv = parse_saved_variables('T = {\n[209] = "a",\n[17] = "b",\n}\nL = {\n"x", "y",\n}\n')
        self.assertEqual(sv['T'], {209: 'a', 17: 'b'})
        self.assertEqual(sv['L'], ['x', 'y'])
        with tempfile.TemporaryDirectory() as addons:
            os.makedirs(os.path.join(addons, 'ForeverLoot'))
            os.makedirs(os.path.join(addons, 'DFLDungeonJournal'))
            with open(os.path.join(addons, 'ForeverLoot', 'Quests.lua'), 'w') as f:
                f.write('ForeverLoot_QuestZones={"Undercity","Tirisfal Glades"}\n'
                        'ForeverLoot_QuestPlaces={\n{1,"Morbin Lightbane",1,57.8,89.8},\n{1,"Deathguard Kristof",2,65.2,60.2},\n}\n'
                        'ForeverLoot_QuestChains={\n{5,7},\n}\n'
                        'ForeverLoot_Quests={\n[9001]={7,8,6},\n}\n'
                        'ForeverLoot_QuestDB={\n[5]={"Start Here",14,12,2,2,2,"Talk.",1},\n'
                        '[7]={"Light\'s Justice",22,15,2,1,1,"Collect 25 Intact Limbs.",1,{1}},\n'
                        '[8]={"Alliance Only",20,15,1,1,1,"No."},\n[6]={"Early One",18,13,3,2,2,"Kill."},\n}\n')
            with open(os.path.join(addons, 'ForeverLoot', 'Data.lua'), 'w') as f:
                f.write('ForeverLoot_DataDate = "2026-09-27"\nForeverLoot_Data = {\n'
                        '{name="Ruins of Lordaeron",zone=9001,kind="dungeon",new=true,levels="15-20",bosses={}},\n}\n')
            with open(os.path.join(addons, 'DFLDungeonJournal', 'QuestRewards.lua'), 'w') as f:
                f.write('local _,J=...\nJ.QuestRewards={\n [7]={choice={{id=1,name="The Stitcher"}},xp=7050,money="45s"},\n}\n'
                        'for k in pairs(J.QuestRewards) do end\n')
            found = dungeon_addons.read(addons)
        ruins = found['list'][0]
        self.assertEqual([q['name'] for q in ruins['quests']], ['Early One', "Light's Justice"])
        justice = ruins['quests'][1]
        self.assertEqual(justice['start'], {'type': 'npc', 'name': 'Morbin Lightbane', 'zone': 'Undercity', 'x': 57.8, 'y': 89.8})
        self.assertEqual(justice['chainFirst'], {'id': 5, 'name': 'Start Here'})
        self.assertEqual(justice['reward'], {'items': ['The Stitcher'], 'xp': 7050, 'money': '45s'})
        self.assertEqual(found['source'], 'Forever Loot + DFL Dungeon Journal')


class UniqueNamesTest(unittest.TestCase):
    def test_same_first_name_gets_last_name_or_number(self):
        from build_roster import unique_names
        realms = {'r': {'chars': [{'name': 'Lovac', 'lastName': 'Kasapin'}, {'name': 'Lovac', 'lastName': None},
                                  {'name': 'Vestac', 'lastName': 'Zla'}]}}
        unique_names(realms)
        self.assertEqual([c['name'] for c in realms['r']['chars']], ['Lovac Kasapin', 'Lovac (2)', 'Vestac'])


class GuideTest(unittest.TestCase):
    def setUp(self):
        self.guide = build_guide.load_guide()  # data/guide.json + the team (personal/ or personal.example/)

    def test_real_guide_is_valid(self):
        build_guide.validate(self.guide)

    def test_validate_rejects_secondary_or_duplicate_professions(self):
        self.guide['characters'][0]['profs'] = ['cook', 'herb']
        with self.assertRaises(SystemExit):
            build_guide.validate(self.guide)
        self.guide['characters'][0]['profs'] = ['herb', 'herb']
        with self.assertRaises(SystemExit):
            build_guide.validate(self.guide)

    def test_validate_rejects_unknown_zone(self):
        self.guide['characters'][0]['zones'].append('Nowhere')
        with self.assertRaises(SystemExit):
            build_guide.validate(self.guide)

    def test_every_send_has_a_matching_get(self):
        chars, profs = self.guide['characters'], self.guide['professions']
        lines = {build_guide.char_label(c): build_guide.supply_lines(c, chars, profs) for c in chars}
        for sender, sent in lines.items():
            for line in sent:
                if not line.startswith('Send '):
                    continue
                item, receivers = line[len('Send '):].rstrip('.').split(' to ')
                for receiver in receivers.split(', '):
                    self.assertTrue(any(l.startswith(f'Get {item} from') and sender in l for l in lines[receiver]),
                                    f'{receiver} does not list getting {item} from {sender}')


class WaitForSaveTest(unittest.TestCase):
    def run_wait(self, mtimes, running=True, timeout=5):
        seq = iter(mtimes)
        last = [None]
        def mtime():
            last[0] = next(seq, last[0])
            return last[0]
        return server.wait_for_save(100, mtime=mtime, running=lambda: running,
                                    timeout=timeout, settle=0, sleep=lambda s: None)

    def test_no_wait_when_the_file_is_newer_than_the_last_sync(self):
        self.assertEqual(self.run_wait([150]), "")

    def test_no_wait_when_the_game_is_closed(self):
        self.assertEqual(self.run_wait([100], running=False), "")

    def test_waits_until_the_game_writes_the_file(self):
        self.assertIn("Waited 2 s", self.run_wait([100, 100, 200, 200, 200]))

    def test_gives_up_after_the_timeout(self):
        self.assertIn("did not save", self.run_wait([100] * 10, timeout=3))


if __name__ == '__main__':
    unittest.main()


class JourneyTest(unittest.TestCase):
    def test_zone_visits_with_levels_and_quests(self):
        import quest_report
        log = {"done": [], "journey": [
            {"k": "zone", "zone": "Tirisfal Glades", "level": 1, "t": 1000},
            {"k": "accept", "zone": "Tirisfal Glades", "level": 1, "t": 1010, "id": 1, "title": "Rude Awakening"},
            {"k": "level", "zone": "Tirisfal Glades", "level": 2, "t": 1100},
            {"k": "zone", "zone": "Brill", "level": 5, "t": 2000},
            {"k": "level", "zone": "Tirisfal Glades", "level": 6, "t": 3000},  # back without a zone event
        ]}
        lines = quest_report.journey_lines(log)
        self.assertIn("**Tirisfal Glades** (level 1-2, level-ups: 2, took 1: Rude Awakening)", lines[2])
        self.assertIn("**Brill** (level 5)", lines[3])
        self.assertIn("**Tirisfal Glades** (level 6", lines[4])
        self.assertEqual(quest_report.journey_lines({}), [])


class AddonPlanTest(unittest.TestCase):
    def test_panel_data(self):
        g = build_guide.load_guide()
        plan = build_guide.addon_plan(g)
        self.assertEqual(plan['classes']['PALADIN']['profs'], ['Mining', 'Skinning'])
        self.assertEqual(plan['camp']['Fishing']['carry'], '5 Raw Brilliant Smallfish, 5 Empty Vial')
        self.assertIn('Herbalism', plan['zones']['The Barrens']['gather'])
        self.assertIn('(50)', plan['zones']['The Barrens']['gather']['Herbalism'])  # skill needed per herb
        self.assertEqual(plan['steps']['Cooking'][0]['recipes'][0]['name'], 'Charred Wolf Meat')
        self.assertTrue(any(l.startswith('Charred Wolf Meat (Cooking)') for l in plan['search']))
        lua = build_guide.to_lua({'a': [1, 'x"y'], 'b': True})
        self.assertIn('"x\\"y"', lua)


class AutoSyncTest(unittest.TestCase):
    def test_new_settled_save_file_syncs_once(self):
        calls, written = [], []
        orig = (server.run_sync_scripts, server.read_last_sync, server.write_last_sync)
        server.run_sync_scripts = lambda: (calls.append(1), (True, ""))[1]
        server.read_last_sync = lambda: 100
        server.write_last_sync = written.append
        try:
            server.watch_save_file(mtime=lambda: 200, now=lambda: 205, once=True)   # new and settled: sync
            server.watch_save_file(mtime=lambda: 200, now=lambda: 201, once=True)   # still being written: wait
            server.watch_save_file(mtime=lambda: 90, now=lambda: 205, once=True)    # nothing new
        finally:
            server.run_sync_scripts, server.read_last_sync, server.write_last_sync = orig
        self.assertEqual(len(calls), 1)
        self.assertEqual(written, [200])
