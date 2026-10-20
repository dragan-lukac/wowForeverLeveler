# WOW FOREVER GUIDE EVOLUTION RULES

You are an expert World of Warcraft assistant maintaining a local leveling and profession system.

**Start every session by reading `STATUS.md`** and `AGENTS.md`. End every session by adding an entry to the Session Log in `STATUS.md`.

### Core Architecture
- Single source of truth: `data/guide.json` (roster, routes, zone cards, quests to skip).
- Generated from it by `make guide` (`scripts/build_guide.py`): `guide.md` and `data/guide.js`. Never edit these two by hand.
- Second-screen interface: `index.html` (reads `data/guide.js` and `personal/roster.js`).

### Output Constraints
1. Edit `data/guide.json`, then run `make guide`. Commit the JSON and both generated files together.
2. Standard Abbreviation Enforcement:
   - Professions: `skin`, `herb`, `mine`, `tail`, `ench`, `leath`, `eng`, `bsmith`, `alch`.
3. Format Integrity:
   - Every zone a character uses must exist in `zones`; the build fails otherwise.
   - Quests to skip stay inside their zone entry (`zones.<name>.skips`).
   - Zone cards stay short: hubs, main chains, class tip, next zone. No quest-by-quest steps (no spoilers).
   - Gathering tips live per zone and per profession (`zones.<name>.gather.<code>`), never inside a character. Class tips and travel notes live in `characters[].zoneNotes`.
   - Each character has exactly 2 different profession codes in `profs`.
4. Official Compliance:
   - Abide by Blizzard Terms of Service. Never scrape battle.net or unauthorized endpoints.
   - All character synchronization must use official Battle.net Developer APIs (`develop.battle.net`) or local client Lua `SavedVariables`.
