"""
Every addon .lua file must compile with Lua 5.1, the game's Lua. A file that does not compile makes the game skip
the whole addon without a word (2026-10-21: a broken Planner.lua hid the minimap button and the window).

Needs lupa (see tests/addon_fakegame.py): the system python3 has none, so the test runs the check with the
/tmp/wfl-lua venv when it exists, and is skipped (with the reason) when neither has lupa.
"""

import glob
import os
import subprocess
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENV = '/tmp/wfl-lua/bin/python'
CHECK = r'''
import glob, sys
import lupa.lua51 as lua51
L = lua51.LuaRuntime()
compile_ = L.eval('function(s, n) local f, e = loadstring(s, "@" .. n); return e end')
bad = []
for f in sorted(glob.glob(sys.argv[1] + '/addon/*/*.lua')):
    with open(f, encoding='utf-8') as fh:
        err = compile_(fh.read(), f[len(sys.argv[1]) + 1:])
    if err:
        bad.append(err)
print('\n'.join(bad))
sys.exit(1 if bad else 0)
'''


def runner():
    try:
        import lupa.lua51  # noqa: F401
        return sys.executable
    except ImportError:
        return VENV if os.path.exists(VENV) else None


class LuaSyntax(unittest.TestCase):
    def test_addon_files_compile_with_lua51(self):
        python = runner()
        if not python:
            self.skipTest('no lupa: python3 -m venv /tmp/wfl-lua && /tmp/wfl-lua/bin/pip install "lupa==2.4"')
        self.assertTrue(glob.glob(os.path.join(ROOT, 'addon', '*', '*.lua')))
        proc = subprocess.run([python, '-c', CHECK, ROOT], capture_output=True, text=True, timeout=120)
        self.assertEqual(proc.returncode, 0, 'Lua 5.1 syntax errors:\n' + proc.stdout + proc.stderr)


if __name__ == '__main__':
    unittest.main()
