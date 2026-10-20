#!/usr/bin/env python3
"""
Launch-day check: `make launch-check`.
Prints OK / WARN / INFO for everything that can be checked from this Mac.
"""

import os
import re
import sys
import glob
import json
import time
import subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_roster import WOW_ROOTS, parse_saved_variables  # noqa: E402
from scraper import load_env  # noqa: E402
import auctionator  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON_TOC = os.path.join(ROOT, 'addon', 'WoWForeverLeveler', 'WoWForeverLeveler.toc')

problems = 0


def report(level, text):
    global problems
    if level == 'WARN':
        problems += 1
    print(f"[{level:4}] {text}")


def toc_version(path):
    with open(path, encoding='utf-8') as f:
        m = re.search(r'## Version:\s*(\S+)', f.read())
    return m.group(1) if m else None


def check_clients():
    wanted = toc_version(ADDON_TOC)
    flavors = []
    for root in WOW_ROOTS:
        for flavor_dir in sorted(glob.glob(os.path.join(root, '_*_'))):
            flavor = os.path.basename(flavor_dir).strip('_')
            flavors.append(flavor)
            toc = os.path.join(flavor_dir, 'Interface', 'AddOns', 'WoWForeverLeveler', 'WoWForeverLeveler.toc')
            if not os.path.exists(toc):
                report('WARN', f"{flavor}: addon not installed. Run: make addon")
            elif toc_version(toc) != wanted:
                report('WARN', f"{flavor}: addon {toc_version(toc)} installed, {wanted} available. Run: make addon")
            else:
                report('OK', f"{flavor}: addon {wanted} installed")
            check_addons(flavor, os.path.join(flavor_dir, 'Interface', 'AddOns'))
            installed_at = os.path.getmtime(toc) if os.path.exists(toc) else 0
            check_save_file(flavor, flavor_dir, installed_at)
    if not flavors:
        report('WARN', "No WoW game folders found in /Applications/World of Warcraft")
    elif flavors == ['classic_beta']:
        report('INFO', "Only the beta client is installed. After the live game installs, run: make addon, then make launch-check again")


def check_addons(flavor, addons_dir):
    """The other addons from guide.json `addons`: needed ones missing = WARN, extra folders = INFO."""
    with open(os.path.join(ROOT, 'data', 'guide.json'), encoding='utf-8') as f:
        plan = json.load(f).get('addons') or {}
    have = set(os.listdir(addons_dir)) if os.path.isdir(addons_dir) else set()
    missing = [a['name'] for a in plan.get('needed', []) if a['folder'] not in have]
    if missing:
        report('WARN', f"{flavor}: addons missing: {', '.join(missing)} (🚀 Launch tab has the list)")
    else:
        report('OK', f"{flavor}: all needed addons installed")
    # The game marks an addon "incompatible" when its ## Interface line misses the client's number.
    # Other addons are updated for each patch, so the number they all share is the current one.
    def interfaces(toc):
        with open(toc, encoding='utf-8', errors='replace') as f:
            m = re.search(r'## Interface:\s*([\d, ]+)', f.read())
        return {x.strip() for x in m.group(1).split(',')} if m else set()
    ours = interfaces(os.path.join(addons_dir, 'WoWForeverLeveler', 'WoWForeverLeveler.toc')) \
        if os.path.exists(os.path.join(addons_dir, 'WoWForeverLeveler', 'WoWForeverLeveler.toc')) else set()
    others = [interfaces(t) for t in glob.glob(os.path.join(addons_dir, '*', '*.toc')) if 'WoWForeverLeveler' not in t]
    shared = set.intersection(*others) if others else set()
    if ours and shared and not (ours & shared):
        report('WARN', f"{flavor}: our addon is marked for game version {', '.join(sorted(ours))}, the other addons for "
                       f"{', '.join(sorted(shared))}. Add it to ## Interface in addon/WoWForeverLeveler/WoWForeverLeveler.toc")
    extra = [a['name'] for a in plan.get('notNeeded', []) if a['folder'] in have]
    if extra:
        report('INFO', f"{flavor}: you can delete these addon folders: {', '.join(extra)}")


def check_save_file(flavor, flavor_dir, installed_at):
    files = glob.glob(os.path.join(flavor_dir, 'WTF', 'Account', '*', 'SavedVariables', 'WoWForeverLeveler.lua'))
    if not files:
        report('INFO', f"{flavor}: no addon save file yet. Log in with a character, then /reload or log out")
        return
    for path in files:
        age_h = (time.time() - os.path.getmtime(path)) / 3600
        with open(path, encoding='utf-8') as f:
            sv = parse_saved_variables(f.read())
        chars = sv.get('WoWForeverLevelerDB') or {}
        realms = sorted({c.get('realm', '?') for c in chars.values()})
        report('OK', f"{flavor}: save file updated {age_h:.1f} hours ago, {len(chars)} characters, realms: {', '.join(realms) or 'none'}")
        auctionator_path = os.path.join(os.path.dirname(path), 'Auctionator.lua')
        items = 0
        if os.path.exists(auctionator_path):
            with open(auctionator_path, 'rb') as f:
                found = auctionator.prices(f.read(), sv.get('WoWForeverLevelerItemIDs') or {},
                                           sv.get('WoWForeverLevelerAuctionRealms') or {}, flavor)
            items = sum(len(v) for v in found.values())
        report('OK' if items else 'INFO', f"{flavor}: {items} items priced by Auctionator" + ('' if items else ' - run an Auctionator full scan at an auction house, then /reload'))
        # Only errors logged after the installed addon version count; older ones were already fixed.
        def logged_at(line):
            try:
                return time.mktime(time.strptime(line[:19], '%Y-%m-%d %H:%M:%S'))
            except ValueError:
                return 0
        errors = [line for line in (sv.get('WoWForeverLevelerLog') or [])
                  if 'error' in line.lower() and logged_at(line) > installed_at]
        if errors:
            report('WARN', f"{flavor}: addon errors since this version was installed, newest: {errors[-1]}")


def check_blizzard_api():
    env = load_env()
    if not env or not env.get('BNET_CLIENT_ID') or 'your_client' in env.get('BNET_CLIENT_ID', ''):
        report('WARN', "No Battle.net keys in .env. Copy .env.example to .env and add your keys")
        return
    import scraper
    token = scraper.get_token(env['BNET_CLIENT_ID'], env['BNET_CLIENT_SECRET'])
    if not token:
        report('WARN', "Battle.net keys rejected. Make a new client secret on develop.battle.net and put it in .env")
        return
    report('OK', "Battle.net keys work")
    region = env.get('BNET_REGION', 'eu').lower()
    # WoW Forever's namespace name is not announced; try likely candidates next to the known Classic ones.
    for ns in [f"dynamic-forever-{region}", f"dynamic-classic-forever-{region}"]:
        url = f"https://{region}.api.blizzard.com/data/wow/connected-realm/index?namespace={ns}&locale=en_US"
        data = scraper.fetch_endpoint(url, token)
        if 'error' in data:
            report('INFO', f"Blizzard WoW Forever data '{ns}': not available yet ({data['error']})")
        else:
            report('OK', f"Blizzard WoW Forever data '{ns}': {len(data.get('connected_realms', []))} realm groups. "
                         "Tell Claude: official auction prices may be possible now")


def check_guide():
    from team import load_guide
    g = load_guide()
    gold = g['money']['mountGoal']['gold']
    report('INFO', f"Mount goal is {gold} gold (Classic value). Update money.mountGoal.gold when Blizzard shows the real cost")
    report('INFO', "Planned races: " + ', '.join(f"{c['race']} {c['class']}" for c in g['characters']) + ". Change them with the plan menu on the dashboard")


def check_tests():
    result = subprocess.run(['make', 'test'], cwd=ROOT, capture_output=True, text=True)
    report('OK' if result.returncode == 0 else 'WARN', "Automatic tests " + ("pass" if result.returncode == 0 else "FAIL: run make test to see why"))


if __name__ == '__main__':
    print("WoW Forever launch check\n")
    check_clients()
    check_blizzard_api()
    check_guide()
    check_tests()
    print(f"\n{'All good.' if not problems else f'{problems} thing(s) need attention (WARN).'}")
