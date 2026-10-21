#!/usr/bin/env python3
"""
Sets up a game client (live, the stress test) the way the beta is set up, in one go. `make live` runs it.

  1. Addons: every addon folder of the beta (where CurseForge installs by default) that the target client does not
     have yet is copied. Folders already there are left alone, so a newer CurseForge version is never overwritten;
     CurseForge finds the copied ones by their files and can update them. Dropped addons
     (settings_transfer.ADDONS_DROPPED) and our own (step 2) are skipped.
  2. Our addons: `make addon`.
  3. Settings: settings_transfer.py import --all, once the client has its WTF folder (start it and log in on each
     character first); otherwise it says so and stops there. Run it again after logging in.

The game must be closed. Safe to run again: it only adds what is missing and redoes the import.

  python3 scripts/live_setup.py                 # into _forever_ (live and the stress test)
  python3 scripts/live_setup.py --client forever --from classic_beta
"""

import argparse
import glob
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import settings_transfer as st  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def addon_names(src_dir):
    """The addon folders of the source client (not Blizzard's own)."""
    return sorted(n for n in os.listdir(src_dir)
                  if os.path.isdir(os.path.join(src_dir, n)) and not n.startswith('Blizzard_'))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--client', default='forever', help='target client folder name (_forever_)')
    ap.add_argument('--from', dest='source', default='classic_beta', help='client to copy addon folders from')
    a = ap.parse_args()
    if os.popen(r'pgrep -f "/Applications/World of Warcraft/_[a-z_]*_/.*\.app/Contents/MacOS/"').read().strip():
        sys.exit('Close the game first.')
    target = os.path.join(st.WOW, f'_{a.client}_')
    if not os.path.isdir(target):
        sys.exit(f'No {target}: install the client with the Battle.net app first.')
    src_dir = os.path.join(st.WOW, f'_{a.source}_', 'Interface', 'AddOns')
    dst_dir = os.path.join(target, 'Interface', 'AddOns')
    os.makedirs(dst_dir, exist_ok=True)

    unpacked = None
    if not os.path.isdir(src_dir):
        # No beta folder (gone after launch): the addons packed in the newest save.
        packs = sorted(glob.glob(os.path.join(st.EXPORT, '*', 'addons.tar.gz')), key=os.path.getmtime)
        if not packs:
            sys.exit(f'No {src_dir} and no addons.tar.gz in a save.')
        import tarfile
        import tempfile
        src_dir = tempfile.mkdtemp(prefix='wfl-addons-')
        with tarfile.open(packs[-1]) as tar:
            tar.extractall(src_dir)
        a.source = os.path.relpath(packs[-1], ROOT)
        unpacked = src_dir
    names = addon_names(src_dir)
    copied, there = [], 0
    for n in names:
        if n in st.ADDONS_DROPPED or n.startswith('WoWForeverLeveler'):
            continue
        if os.path.isdir(os.path.join(dst_dir, n)):
            there += 1
        elif os.path.isdir(os.path.join(src_dir, n)):
            shutil.copytree(os.path.join(src_dir, n), os.path.join(dst_dir, n))
            copied.append(n)
    if unpacked:
        shutil.rmtree(unpacked, ignore_errors=True)
    print(f'1. Addons from {a.source}: {len(copied)} copied' + (f' ({", ".join(copied)})' if copied else '')
          + f', {there} already there')

    proc = subprocess.run(['make', 'addon'], cwd=ROOT, capture_output=True, text=True)
    ok = proc.returncode == 0 and os.path.isdir(os.path.join(dst_dir, 'WoWForeverLeveler'))
    print('2. Our addons: ' + ('installed' if ok else 'make addon failed:\n' + proc.stdout[-500:] + proc.stderr[-500:]))

    if not glob.glob(os.path.join(target, 'WTF', 'Account', '*', '*', '*', 'config-cache.wtf')):
        print('3. Settings: not yet. Start the game, log in on each character once, close it, run this again.')
        return
    proc = subprocess.run([sys.executable, os.path.join(ROOT, 'scripts', 'settings_transfer.py'), 'import',
                           '--client', a.client, '--all'], cwd=ROOT, capture_output=True, text=True)
    print('3. Settings:\n   ' + (proc.stdout + proc.stderr).strip().replace('\n', '\n   '))


if __name__ == '__main__':
    main()
