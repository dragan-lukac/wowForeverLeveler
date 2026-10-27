#!/usr/bin/env python3
"""
Refreshes the data files built from the QuestieDB addon, so they never go stale after a QuestieDB or Forever Loot
update. Runs on every Sync (scripts/server.py) and every `make guide`, before build_guide.py; about 3 seconds.

  - data/dungeon_givers.json (scripts/dungeon_givers.py): where each dungeon quest's giver really is.
  - data/vendor_items.json (scripts/vendor_items.py): which vendors sell each crafting material; the trainers.
  - data/dungeon_levels.json (scripts/dungeon_levels.py): the real monster levels in each dungeon.
  - data/reagent_drops.json (scripts/reagent_drops.py): which monsters drop each Cooking / First Aid material.
  - data/rares.json (scripts/rares.py): where the rares of guide.json `rares` stand, their level and drops.

Without QuestieDB installed (a fresh live install), or when a script fails, the last files stay and the sync goes on.
"""

import contextlib
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import questie_db  # noqa: E402


def main():
    if not questie_db.toc_path():
        print('[refresh] QuestieDB not installed: dungeon givers and vendor lists kept as they are')
        return
    import dungeon_givers
    import dungeon_levels
    import reagent_drops
    import rares
    import vendor_items
    for name, mod in (('dungeon givers', dungeon_givers), ('vendor lists', vendor_items), ('dungeon levels', dungeon_levels),
                      ('material drops', reagent_drops), ('rares', rares)):
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out):
                mod.main()
            print(f'[refresh] {name}: {out.getvalue().splitlines()[0] if out.getvalue() else "done"}')
        except Exception as e:  # keep the last file; never stop the sync
            print(f'[refresh] {name} failed, last file kept: {e}')


if __name__ == '__main__':
    main()
