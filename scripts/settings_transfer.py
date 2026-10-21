#!/usr/bin/env python3
"""
Copies the game's interface setup from one template character to the whole team, and keeps a copy for live.

The game must be closed: it writes these files at logout and would overwrite our changes.

  python3 scripts/settings_transfer.py apply  --client classic_beta --from Kaspin-Lovac
  python3 scripts/settings_transfer.py export --client classic_beta --from Kaspin-Lovac
  python3 scripts/settings_transfer.py import --client forever
  python3 scripts/settings_transfer.py import --client forever --all   (every character, e.g. the stress test)

What the files hold (WTF/Account/<account>/...):
- Account-wide, shared by every character already: key bindings (bindings-cache.wtf), account macros,
  interface options (config-cache.wtf), the Edit Mode layouts (edit-mode-cache-account.txt), addon settings
  (SavedVariables/*.lua).
- Per character (<realm>/<First-Last>/): which Edit Mode layout it uses (edit-mode-cache-character.txt), the
  extra action bars and the Cooldown Manager switch (config-cache.wtf), window positions (layout-local.txt),
  chat windows (chat-cache.txt), click bindings, and which addons are on (AddOns.txt).
- Not copied: the Cooldown Manager spells (cooldownmanager.txt) and character macros, they are per class;
  action bar contents live on the server.

`apply` points every team character (personal/team.json) at the template's layout and copies its per-character
files. The pet bar is part of the layout, so a warlock's demon bar gets the same spot; classes without a pet
never show it. `export` saves the account files, the template's files and the graphics and sound lines of
Config.wtf in personal/settings-backup/. `import` puts them into another client (live) and runs `apply` there.
Every write keeps the old file as <name>.wfl-bak.
"""

import argparse
import datetime
import glob
import json
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WOW = os.environ.get('WFL_WOW', '/Applications/World of Warcraft')  # WFL_WOW: a copy, for tests
EXPORT = os.path.join(ROOT, 'personal', 'settings-backup')
TEAM = os.path.join(ROOT, 'personal', 'team.json')

ACCOUNT_FILES = ['bindings-cache.wtf', 'config-cache.wtf', 'edit-mode-cache-account.txt', 'macros-cache.txt']
# Addon settings, not data: price databases and our own beta data stay behind.
SKIP_SAVED = re.compile(r'^(Auctionator|WoWForeverLeveler|Blizzard_PTRFeedback)', re.I)
# From those two, only the settings tables are saved (partial/<file>.lua) and merged back on import; the data tables
# (prices, scans, our beta recipes and trainers) stay behind. Per table: keys that are data, left out too.
PARTIAL_SAVED = {
    'WoWForeverLeveler': {'WoWForeverLevelerUI': ['have', 'selected']},  # window spot, size, text size, minimap angle
    'Auctionator': {'AUCTIONATOR_CONFIG': [], 'AUCTIONATOR_SHOPPING_LISTS': [], 'AUCTIONATOR_SELLING_GROUPS': []},
}


def lua_block(text, name):
    """The `name = ...` top-level assignment of a SavedVariables file (a table ends at a '}' alone on a line)."""
    m = re.search(rf'(?m)^{re.escape(name)} = ', text)
    if not m:
        return None
    if text[m.end():m.end() + 1] != '{':
        return text[m.start():text.find('\n', m.start()) + 1 or len(text)]
    end = re.compile(r'(?m)^}\r?$').search(text, m.end())
    return text[m.start():end.end()] + '\n' if end else None


def strip_keys(block, keys):
    """The table without its first-level ["key"] entries listed in keys (WoW writes one entry per line)."""
    out, depth, skip_until = [], 0, None
    for line in block.splitlines():
        t = line.strip()
        if skip_until is not None:
            if t.endswith('{'):
                depth += 1
            elif t.startswith('}'):
                depth -= 1
            if depth == skip_until:
                skip_until = None
            continue
        km = re.match(r'\["([^"]+)"\] = ', t)
        if depth == 1 and km and km.group(1) in keys:
            if t.endswith('{'):
                skip_until, depth = depth, depth + 1
            continue
        if t.endswith('{'):
            depth += 1
        elif t.startswith('}'):
            depth -= 1
        out.append(line)
    return '\n'.join(out) + '\n'


def merge_block(text, name, block):
    """text with its `name = ...` block replaced by block, or block added at the end."""
    old = lua_block(text, name)
    if old:
        return text.replace(old, block, 1)
    return (text.rstrip('\n') + '\n' if text.strip() else '') + block
# Edit Mode Tweaks keeps its hide rules account-wide (SavedVariables/EditModeTweaks.lua), so the account export has them.
# AddOns.txt (which addons are on) is not copied: the game writes "disabled" for all after "disable all", and that list
# went to every character once (2026-10-21). addon_list() writes it fresh instead.
CHAR_COPY = ['layout-local.txt', 'chat-cache.txt', 'click-bindings-cache.txt',
             # addons that keep (some) settings per character, the same for every class
             'SavedVariables/MinimapButtonForever.lua', 'SavedVariables/OPie.lua', 'SavedVariables/Auctionator.lua']
# Per class, saved for each team character and put back on the character of the same class on live.
CLASS_FILES = ['cooldownmanager.txt', 'macros-cache.txt', 'SavedVariables/GearQuestForever.lua',
               'SavedVariables/ShotWindow.lua']  # Shot Window: hunter / wand aim timer, per character
# Account settings the import always sets, whatever the export holds: new quests do not go to Blizzard's quest
# list (it shows only when you track a quest yourself; Polestar guides instead). User, 2026-10-21.
ACCOUNT_CVARS = {'autoQuestWatch': '0', 'autoQuestProgress': '0'}
CHAR_CVARS = ['enableMultiActionBars', 'cooldownViewerEnabled']
# Config.wtf lines that belong to one install or account, not to the graphics and sound setup.
CONFIG_SKIP = re.compile(r'^SET (portal|accountName|accountList|realmName|realmList|lastCharacterIndex|'
                         r'lastAccountName|g_|installLocale|textLocale|audioLocale|agentUID|launcher|'
                         r'checkAddonVersion|engineSurvey|hwDetect|lastAddonVersion|gxAdapter)', re.I)


def account_dir(client):
    dirs = [d for d in glob.glob(os.path.join(WOW, f'_{client}_', 'WTF', 'Account', '*'))
            if os.path.isdir(d) and os.path.basename(d) != 'SavedVariables']
    if len(dirs) != 1:
        sys.exit(f'Expected one account folder for _{client}_, found: {dirs or "none (start the game once)"}')
    return dirs[0]


def char_dirs(acct):
    """{ 'First-Last': path } for every character folder of every realm."""
    out = {}
    for realm in os.listdir(acct):
        rp = os.path.join(acct, realm)
        if os.path.isdir(rp) and realm != 'SavedVariables':
            for c in os.listdir(rp):
                if os.path.isdir(os.path.join(rp, c)):
                    out[c] = os.path.join(rp, c)
    return out


def team_by_class():
    """{ 'hunter': 'Kaspin-Lovac', ..., 'bank': 'Banka-Posta' } from personal/team.json."""
    with open(TEAM, encoding='utf-8') as f:
        team = json.load(f)
    chars = dict(team.get('characters', {}))
    if team.get('bank'):
        chars['bank'] = team['bank']
    return {k: f"{c['name']}-{c['lastName']}" for k, c in chars.items() if c.get('name') and c.get('lastName')}


def team_folders():
    return list(team_by_class().values())


def write(path, text):
    if os.path.exists(path):
        shutil.copy2(path, path + '.wfl-bak')
    # surrogateescape: bytes that are not UTF-8 (Auctionator's file has some) go back out unchanged.
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def active_layout(text):
    """edit-mode-cache-character.txt: version, then 10 spec slots (layout number, -1 = none), then the
    character's own layouts. Returns the template's layout number."""
    t = text.split()
    used = [x for x in t[1:11] if x != '-1']
    if not used:
        sys.exit('The template character uses no saved layout: pick one in Edit Mode first.')
    return used[0]


def set_layout(text, layout):
    t = text.split(' ')
    if len(t) < 6:
        return f'5 {layout} {layout} {layout} {layout} {layout} -1 -1 -1 -1 -1 '
    for i in range(1, 6):
        t[i] = layout
    return ' '.join(t)


def set_cvars(text, values):
    for name, value in values.items():
        line = f'SET {name} "{value}"'
        pat = re.compile(rf'^SET {name} ".*?"(?=\r?$)', re.M)
        nl = '\r\n' if '\r\n' in text else '\n'
        text = pat.sub(line, text) if pat.search(text) else text.rstrip('\r\n') + nl + line + nl
    return text


def template_parts(tdir):
    layout = active_layout(read(os.path.join(tdir, 'edit-mode-cache-character.txt')))
    cfg = read(os.path.join(tdir, 'config-cache.wtf'))
    cvars = {m.group(1): m.group(2) for m in re.finditer(r'^SET (\w+) "(.*?)"\r?$', cfg, re.M) if m.group(1) in CHAR_CVARS}
    files = {n: read(os.path.join(tdir, n)) for n in CHAR_COPY if os.path.exists(os.path.join(tdir, n))}
    return layout, cvars, files


# Installed but left off: dropped addons (Follow The Arrow flooded errors; the others are replaced by our data or
# Polestar), and Blizzard's quest sidebar (Polestar shows the steps).
# Dropped: not copied, not packed. Off: installed (packed, copied to live) but turned off in the game; Questie and
# QuestieDB are off because our Sync only reads QuestieDB's files on disk.
ADDONS_DROPPED = {'FollowTheArrow', 'ForeverGuide', 'DFLDungeonJournal', 'ForeverLoot'}
ADDONS_OFF = ADDONS_DROPPED | {'Questie', 'QuestieDB', 'Blizzard_ObjectiveTracker'}


def addon_list(acct):
    """AddOns.txt for a character: every installed addon enabled, except ADDONS_OFF (the game's own CRLF lines)."""
    addons_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(acct))), 'Interface', 'AddOns')
    names = sorted(os.path.basename(os.path.dirname(d)) for d in glob.glob(os.path.join(addons_dir, '*', ''))
                   if not os.path.basename(os.path.dirname(d)).startswith('Blizzard_'))
    lines = [f"{n}: {'disabled' if n in ADDONS_OFF else 'enabled'}" for n in names]
    lines.append('Blizzard_ObjectiveTracker: disabled')
    return '\r\n'.join(lines) + '\r\n'


def apply_to(acct, layout, cvars, files, skip=None, everyone=False):
    """The template's setup on every team character (personal/team.json), or with everyone=True on every
    character folder of the account (a test client with other names)."""
    chars = char_dirs(acct)
    addons = addon_list(acct)
    done, missing = [], []
    for name in (sorted(chars) if everyone else team_folders()):
        cdir = chars.get(name)
        if not cdir:
            missing.append(name)
            continue
        if name == skip:
            continue
        p = os.path.join(cdir, 'edit-mode-cache-character.txt')
        write(p, set_layout(read(p) if os.path.exists(p) else '', layout))
        p = os.path.join(cdir, 'config-cache.wtf')
        write(p, set_cvars(read(p) if os.path.exists(p) else '', cvars))
        for n, text in files.items():
            os.makedirs(os.path.dirname(os.path.join(cdir, n)), exist_ok=True)
            write(os.path.join(cdir, n), text)
        write(os.path.join(cdir, 'AddOns.txt'), addons)
        done.append(name)
    print(f'Layout {layout}, {", ".join(f"{k}={v}" for k, v in cvars.items())}, files: {", ".join(files)}, AddOns.txt '
          f'({addons.count("enabled")} addons on)')
    print('Applied to: ' + (', '.join(done) or 'nobody'))
    if missing:
        print('No folder yet (log in once): ' + ', '.join(missing))


def classes_from_save(acct):
    """{ 'First-Last': 'hunter', ... } from WoWForeverLevelerDB in the account's save file, if our addon ran."""
    path = os.path.join(acct, 'SavedVariables', 'WoWForeverLeveler.lua')
    if not os.path.exists(path):
        return {}
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from build_roster import parse_saved_variables
    db = parse_saved_variables(read(path)).get('WoWForeverLevelerDB') or {}
    return {f"{c['name']}-{c['lastName']}": c['class'].lower() for c in db.values()
            if isinstance(c, dict) and c.get('name') and c.get('lastName') and c.get('class')}


def cmd_apply(a):
    acct = account_dir(a.client)
    tdir = char_dirs(acct).get(a.template) or sys.exit(f'No character folder {a.template}')
    apply_to(acct, *template_parts(tdir), skip=a.template)


def cmd_export(a):
    acct = account_dir(a.client)
    tdir = char_dirs(acct).get(a.template) or sys.exit(f'No character folder {a.template}')
    # One folder per day and client, so a stress test export does not replace the beta one.
    out = os.path.join(EXPORT, f'{datetime.date.today().isoformat()}-{a.client}')
    os.makedirs(os.path.join(out, 'account', 'SavedVariables'), exist_ok=True)
    os.makedirs(os.path.join(out, 'template'), exist_ok=True)
    for n in ACCOUNT_FILES:
        if os.path.exists(os.path.join(acct, n)):
            shutil.copy2(os.path.join(acct, n), os.path.join(out, 'account', n))
    saved = []
    for p in sorted(glob.glob(os.path.join(acct, 'SavedVariables', '*.lua'))):
        if not SKIP_SAVED.match(os.path.basename(p)):
            shutil.copy2(p, os.path.join(out, 'account', 'SavedVariables'))
            saved.append(os.path.basename(p)[:-4])
    os.makedirs(os.path.join(out, 'account', 'partial'), exist_ok=True)
    for f, tables in PARTIAL_SAVED.items():
        p = os.path.join(acct, 'SavedVariables', f + '.lua')
        if os.path.exists(p):
            text = read(p)
            blocks = []
            for n, keys in tables.items():
                b = lua_block(text, n)
                if b:
                    blocks.append(strip_keys(b, keys))
            if blocks:
                write(os.path.join(out, 'account', 'partial', f + '.lua'), ''.join(blocks))
                saved.append(f + ' (settings only)')
    for n in CHAR_COPY + ['edit-mode-cache-character.txt', 'config-cache.wtf']:
        if os.path.exists(os.path.join(tdir, n)):
            os.makedirs(os.path.dirname(os.path.join(out, 'template', n)), exist_ok=True)
            shutil.copy2(os.path.join(tdir, n), os.path.join(out, 'template', n))
    chars, classes = char_dirs(acct), []
    # Team names, or (other names, a test client) each character's class from our addon's save file there.
    pairs = {cls: name for cls, name in team_by_class().items() if name in chars}
    for name, cls in classes_from_save(acct).items():
        if name in chars and cls not in pairs:
            pairs[cls] = name
    for cls, name in pairs.items():
        for n in CLASS_FILES:
            p = os.path.join(chars.get(name, ''), n)
            if chars.get(name) and os.path.exists(p):
                os.makedirs(os.path.dirname(os.path.join(out, 'class', cls, n)), exist_ok=True)
                shutil.copy2(p, os.path.join(out, 'class', cls, n))
                classes.append(cls)
    # The installed addons with their versions: what to install on live before the import.
    inv = []
    for d in sorted(glob.glob(os.path.join(WOW, f'_{a.client}_', 'Interface', 'AddOns', '*', ''))):
        name = os.path.basename(os.path.dirname(d))
        if name.startswith('Blizzard_'):
            continue
        tocs = sorted(glob.glob(os.path.join(d, '*.toc')))
        title = version = ''
        for line in (read(tocs[0]).splitlines() if tocs else []):
            if line.startswith('## Title:') and not title:
                title = re.sub(r'\|c\w{8}|\|r', '', line.split(':', 1)[1]).strip()
            if line.startswith('## Version:') and not version:
                version = line.split(':', 1)[1].strip()
        inv.append(f'{name}\t{version}\t{title}')
    # The addon folders themselves, packed (not Blizzard's, not ours: `make addon` builds those, not the dropped
    # ones): make live unpacks the missing ones when the beta folder is gone.
    import tarfile
    addons_dir = os.path.join(WOW, f'_{a.client}_', 'Interface', 'AddOns')
    keep = [n.split('\t')[0] for n in inv]
    keep = [n for n in keep if not n.startswith('WoWForeverLeveler') and n not in ADDONS_DROPPED]
    with tarfile.open(os.path.join(out, 'addons.tar.gz'), 'w:gz') as tar:
        for n in keep:
            tar.add(os.path.join(addons_dir, n), arcname=n)
    with open(os.path.join(out, 'addons.txt'), 'w', encoding='utf-8') as f:
        f.write('# Folder\tVersion\tTitle (installed on ' + a.client + ' when exported)\n' + '\n'.join(inv) + '\n')
    config = os.path.join(WOW, f'_{a.client}_', 'WTF', 'Config.wtf')
    lines = [l for l in read(config).splitlines() if l.startswith('SET ') and not CONFIG_SKIP.match(l)]
    with open(os.path.join(out, 'Config-graphics.wtf'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    print(f'Saved in {os.path.relpath(out, ROOT)}: account files, addon settings ({", ".join(saved)}),'
          f' template {a.template}, {len(lines)} graphics and sound lines,'
          f' per-class files for: {", ".join(sorted(set(classes))) or "nobody"}; addon list ({len(inv)} folders) in addons.txt.')


def cmd_import(a):
    dirs = sorted(glob.glob(os.path.join(EXPORT, '*', 'Config-graphics.wtf')), key=os.path.getmtime)
    src = a.source or (os.path.dirname(dirs[-1]) if dirs else sys.exit('Nothing exported yet.'))
    acct = account_dir(a.client)
    for n in ACCOUNT_FILES:
        if os.path.exists(os.path.join(src, 'account', n)):
            write(os.path.join(acct, n), read(os.path.join(src, 'account', n)))
    p = os.path.join(acct, 'config-cache.wtf')
    write(p, set_cvars(read(p) if os.path.exists(p) else '', ACCOUNT_CVARS))
    os.makedirs(os.path.join(acct, 'SavedVariables'), exist_ok=True)
    for p in glob.glob(os.path.join(src, 'account', 'SavedVariables', '*.lua')):
        write(os.path.join(acct, 'SavedVariables', os.path.basename(p)), read(p))
    # Settings-only tables (our window, Auctionator's options): merged into the files there, their data kept.
    for p in glob.glob(os.path.join(src, 'account', 'partial', '*.lua')):
        target = os.path.join(acct, 'SavedVariables', os.path.basename(p))
        text = read(target) if os.path.exists(target) else ''
        part = read(p)
        for f, tables in PARTIAL_SAVED.items():
            if f + '.lua' == os.path.basename(p):
                for n in tables:
                    b = lua_block(part, n)
                    if b:
                        text = merge_block(text, n, b)
        write(target, text)
    config = os.path.join(WOW, f'_{a.client}_', 'WTF', 'Config.wtf')
    values = dict(re.findall(r'^SET (\w+) "(.*?)"\r?$', read(os.path.join(src, 'Config-graphics.wtf')), re.M))
    write(config, set_cvars(read(config) if os.path.exists(config) else '', values))
    t = os.path.join(src, 'template')
    layout = active_layout(read(os.path.join(t, 'edit-mode-cache-character.txt')))
    cfg = read(os.path.join(t, 'config-cache.wtf'))
    cvars = {m.group(1): m.group(2) for m in re.finditer(r'^SET (\w+) "(.*?)"\r?$', cfg, re.M) if m.group(1) in CHAR_CVARS}
    files = {n: read(os.path.join(t, n)) for n in CHAR_COPY if os.path.exists(os.path.join(t, n))}
    print(f'Imported {os.path.relpath(src, ROOT)}: account files, addon settings, {len(values)} graphics lines.')
    apply_to(acct, layout, cvars, files, everyone=a.everyone)
    chars, put = char_dirs(acct), []
    targets = list(team_by_class().items())
    if a.everyone:
        # Other names (a test client): each character's class from our addon's save file there.
        targets = [(cls, name) for name, cls in classes_from_save(acct).items()] or targets
    for cls, name in targets:
        cdir = os.path.join(src, 'class', cls)
        if chars.get(name) and os.path.isdir(cdir):
            for n in CLASS_FILES:
                if os.path.exists(os.path.join(cdir, n)):
                    os.makedirs(os.path.dirname(os.path.join(chars[name], n)), exist_ok=True)
                    write(os.path.join(chars[name], n), read(os.path.join(cdir, n)))
            put.append(name)
    print('Cooldown Manager spells and character macros for: ' + (', '.join(put) or 'nobody'))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    for name, fn in (('apply', cmd_apply), ('export', cmd_export), ('import', cmd_import)):
        p = sub.add_parser(name)
        p.add_argument('--client', default='classic_beta' if name != 'import' else 'forever')
        if name != 'import':
            p.add_argument('--from', dest='template', required=True, help='template character folder, e.g. Kaspin-Lovac')
        else:
            p.add_argument('--source', help='an export folder (default: the newest)')
            p.add_argument('--all', dest='everyone', action='store_true',
                           help='every character folder, not only the team (a test client with other names)')
        p.set_defaults(fn=fn)
    a = ap.parse_args()
    if os.popen(r'pgrep -f "/Applications/World of Warcraft/_[a-z_]*_/.*\.app/Contents/MacOS/"').read().strip():
        sys.exit('Close the game first: it writes these files at logout.')
    a.fn(a)


if __name__ == '__main__':
    main()
