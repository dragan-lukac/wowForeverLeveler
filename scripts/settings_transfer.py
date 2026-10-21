#!/usr/bin/env python3
"""
Copies the game's interface setup from one template character to the whole team, and keeps a copy for live.

The game must be closed: it writes these files at logout and would overwrite our changes.

  python3 scripts/settings_transfer.py apply  --client classic_beta --from Kaspin-Lovac
  python3 scripts/settings_transfer.py export --client classic_beta --from Kaspin-Lovac
  python3 scripts/settings_transfer.py import --client forever

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
CHAR_COPY = ['layout-local.txt', 'chat-cache.txt', 'click-bindings-cache.txt', 'AddOns.txt',
             # per-character addon settings: Edit Mode Tweaks keeps its hide rules (mouse-over, combat, target) here
             'SavedVariables/EditModeTweaks.lua']
# Per class, saved for each team character and put back on the character of the same class on live.
CLASS_FILES = ['cooldownmanager.txt', 'macros-cache.txt']
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
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)


def read(path):
    with open(path, encoding='utf-8', newline='') as f:
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


def apply_to(acct, layout, cvars, files, skip=None):
    chars = char_dirs(acct)
    done, missing = [], []
    for name in team_folders():
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
        done.append(name)
    print(f'Layout {layout}, {", ".join(f"{k}={v}" for k, v in cvars.items())}, files: {", ".join(files)}')
    print('Applied to: ' + (', '.join(done) or 'nobody'))
    if missing:
        print('No folder yet (log in once): ' + ', '.join(missing))


def cmd_apply(a):
    acct = account_dir(a.client)
    tdir = char_dirs(acct).get(a.template) or sys.exit(f'No character folder {a.template}')
    apply_to(acct, *template_parts(tdir), skip=a.template)


def cmd_export(a):
    acct = account_dir(a.client)
    tdir = char_dirs(acct).get(a.template) or sys.exit(f'No character folder {a.template}')
    out = os.path.join(EXPORT, datetime.date.today().isoformat())
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
    for n in CHAR_COPY + ['edit-mode-cache-character.txt', 'config-cache.wtf']:
        if os.path.exists(os.path.join(tdir, n)):
            os.makedirs(os.path.dirname(os.path.join(out, 'template', n)), exist_ok=True)
            shutil.copy2(os.path.join(tdir, n), os.path.join(out, 'template', n))
    chars, classes = char_dirs(acct), []
    for cls, name in team_by_class().items():
        for n in CLASS_FILES:
            p = os.path.join(chars.get(name, ''), n)
            if chars.get(name) and os.path.exists(p):
                os.makedirs(os.path.join(out, 'class', cls), exist_ok=True)
                shutil.copy2(p, os.path.join(out, 'class', cls, n))
                classes.append(cls)
    config = os.path.join(WOW, f'_{a.client}_', 'WTF', 'Config.wtf')
    lines = [l for l in read(config).splitlines() if l.startswith('SET ') and not CONFIG_SKIP.match(l)]
    with open(os.path.join(out, 'Config-graphics.wtf'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    print(f'Saved in {os.path.relpath(out, ROOT)}: account files, addon settings ({", ".join(saved)}),'
          f' template {a.template}, {len(lines)} graphics and sound lines,'
          f' Cooldown Manager spells and character macros for: {", ".join(sorted(set(classes))) or "nobody"}.')


def cmd_import(a):
    dirs = sorted(glob.glob(os.path.join(EXPORT, '*')))
    src = a.source or (dirs[-1] if dirs else sys.exit('Nothing exported yet.'))
    acct = account_dir(a.client)
    for n in ACCOUNT_FILES:
        if os.path.exists(os.path.join(src, 'account', n)):
            write(os.path.join(acct, n), read(os.path.join(src, 'account', n)))
    os.makedirs(os.path.join(acct, 'SavedVariables'), exist_ok=True)
    for p in glob.glob(os.path.join(src, 'account', 'SavedVariables', '*.lua')):
        write(os.path.join(acct, 'SavedVariables', os.path.basename(p)), read(p))
    config = os.path.join(WOW, f'_{a.client}_', 'WTF', 'Config.wtf')
    values = dict(re.findall(r'^SET (\w+) "(.*?)"\r?$', read(os.path.join(src, 'Config-graphics.wtf')), re.M))
    write(config, set_cvars(read(config) if os.path.exists(config) else '', values))
    t = os.path.join(src, 'template')
    layout = active_layout(read(os.path.join(t, 'edit-mode-cache-character.txt')))
    cfg = read(os.path.join(t, 'config-cache.wtf'))
    cvars = {m.group(1): m.group(2) for m in re.finditer(r'^SET (\w+) "(.*?)"\r?$', cfg, re.M) if m.group(1) in CHAR_CVARS}
    files = {n: read(os.path.join(t, n)) for n in CHAR_COPY if os.path.exists(os.path.join(t, n))}
    print(f'Imported {os.path.relpath(src, ROOT)}: account files, addon settings, {len(values)} graphics lines.')
    apply_to(acct, layout, cvars, files)
    chars, put = char_dirs(acct), []
    for cls, name in team_by_class().items():
        cdir = os.path.join(src, 'class', cls)
        if chars.get(name) and os.path.isdir(cdir):
            for n in os.listdir(cdir):
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
        p.set_defaults(fn=fn)
    a = ap.parse_args()
    if os.popen(r'pgrep -f "/Applications/World of Warcraft/_[a-z_]*_/.*\.app/Contents/MacOS/"').read().strip():
        sys.exit('Close the game first: it writes these files at logout.')
    a.fn(a)


if __name__ == '__main__':
    main()
