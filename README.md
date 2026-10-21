# WoW Forever Leveler

Leveling, profession and money dashboard for 9 Horde characters and a bank character in
World of Warcraft: Forever. Where the project stands and what is planned: `STATUS.md`.

## Start and stop

- **Start:** click **WFL Dashboard** in the Dock. It starts the dashboard and opens it in Chrome. If the
  dashboard tab is already open, it brings that tab to the front.
- **Is it on?** A dot under the Dock icon.
- **Stop:** right-click the Dock icon → **Quit**.
- The app is `Launchers/WFL Dashboard.app`. Its source is `Launchers/WFL Dashboard.applescript`
  (rebuild with `osacompile -s -o "WFL Dashboard.app" "WFL Dashboard.applescript"`, then put the Horde
  icon back into `Contents/Resources/applet.icns`).
- `Launchers/Sync Characters.app` logs in to Battle.net and updates Classic Era characters.
- Logs: `/tmp/wowforever-dashboard.log` and `/tmp/wowforever-sync.log`.

## The dashboard

Top tabs:

| Tab | What it shows |
| :--- | :--- |
| 🚀 **Launch** | Launch checklist with countdown. Some steps tick themselves. The tab hides when all steps are done. |
| 👥 **Characters** | One card per character with its next 2 steps. Grey cards are planned characters you have not created yet. |
| ⚒ **Professions** | Trainers (where they stand, which you still need), Recipes, Camping, Merchant's Favor. |
| 🏦 **Auction House** | Buy & Sell signals and craft ideas, Money methods with today's profit, Mount gold per character. |

Click a character for 3 small tabs:
- **🧭 Route:** everything in level order: zone, class quests, quests to skip (elite, with links), what to
  gather, what to sell or mail, profession training, what to craft for the next skill points, weapon and
  wand upgrades. Your current step has a gold frame. Done steps fold away.
- **⚒ Professions:** the current profession step with materials, best recipes, trainer hints.
- **💰 Money:** for each item you get in your zone: keep, mail to your crafter, vendor, hold, or sell on the
  auction house at an exact price. Also money methods and crafts with profit now.

Top bar: realm menu, text size (A− A+), **⟳ Sync** (reads the in-game addon; it waits up to 1 minute for
the game to save), **+ Battle.net** (also syncs Classic Era characters).

## In game

| What | How |
| :--- | :--- |
| Save your data | `/reload` or log out. Then click **⟳ Sync** on the dashboard. |
| Auction prices | Install **Auctionator**. At the auction house, run its full scan. Then `/reload` and Sync. |
| Trainers you still need | Opens by itself in a city. Macro: `/wfl todo` to show or hide it. |
| Test the game client | `/wfl check` |

The addon also saves, by itself: level, gold, professions, recipes (open each profession window once),
trainer lists and positions (open the trainer once), recipe vendors, quests, and vendor prices.

## Launch day (November 4)

1. Install the live client in the Battle.net app (it uses the `_forever_` folder, like the stress test).
2. Close the game and run `make live`: it copies every addon from the beta that live lacks, and installs ours.
3. Start the game, create the characters, log in on each one once, then close the game.
4. Run `make live` again: it imports the settings (layout, key bindings, macros, addon settings, graphics).
5. Point CurseForge at the `_forever_` folder; it finds the copied addons and keeps them updated.
6. On each character: `/reload` once, then **⟳ Sync**. The live realm appears in the realm menu.

## Terminal commands

Run these in the project folder.

| Command | What it does |
| :--- | :--- |
| `make` | Shows this list. |
| `make serve` | Starts the dashboard without the Dock app. Open http://localhost:8765/ |
| `make guide` | Rebuilds `guide.md`, `data/guide.js` and the addon's item and trainer lists from `data/guide.json`. |
| `make roster` | Updates the dashboard from the addon save files. |
| `make addon` | Installs the addon into every WoW client on this Mac (beta, and live at launch). |
| `make live` | Sets up the live client: missing addons from the beta, ours, then your settings. Game closed. |
| `make test` | Runs the automatic tests. |
| `make launch-check` | Checks game folders, addon versions, save files, Blizzard keys, and runs the tests. |
| `make refresh` / `make sync` | Battle.net login and character sync (Classic Era). |
| `make check` | Tests your Battle.net keys in `.env`. |
| `make quests` | Writes `personal/quest_report.md`: your real quests compared with the guide. |

## Guide data

- Edit only `data/guide.json`, then run `make guide` or click **⟳ Sync**. `STATUS.md` lists its keys.
- Mark a checked zone card: `"checked": {"date": "2026-09-28", "client": "beta"}`.
- Quest skips (elite quests) and weapon paths come from ClassicDB (classicdb.ch). They are Classic data and
  show "not checked" until you confirm them.
- Money methods live in `money.methods`. Add your own disenchant results to `calc.observed`.
- Professions: if the addon knows a character's professions, the dashboard uses them ("from game");
  otherwise the plan. Change the plan on a planned character's page.
- History: each Sync copies prices, recipes, level and gold into `personal/history.sqlite` and keeps a daily
  backup in `personal/backups/` (last 7). Neither is in git. Beta and live data are kept apart.

## Ports

- `8765`: the dashboard.
- `8000`: the Battle.net login. Do not use it for anything else.

## First-time setup

1. Copy `.env.example` to `.env`.
2. Put your keys from https://develop.battle.net/access/clients into `.env`.
3. Your team: copy `personal.example/team.json` to `personal/team.json` and set each character's name, race,
   professions and play order (without it the example team is used).
4. Run `make guide`, then `make check`.

## Personal data

Everything about you lives in `personal/` and is not in git: your team (`team.json`), your Battle.net and local
character lists, the synced roster (`roster.js`), the history database and its backups. The files built from your
team (`data/guide.js`, `data/addon_plan.js`, `guide.md`, the addon's `Plan.lua`) are not in git either:
`make guide` builds them (`make test` and `make addon` do it first).

## Files

- `STATUS.md`: project state, plan and session routine. Tell any AI agent: "Read STATUS.md and continue."
- `data/guide.json`: the plan (source of truth). `guide.md`: the plan as text (generated).
- `index.html` and `js/`: the dashboard. `scripts/`: sync and server. `addon/WoWForeverLeveler/`: the addon.
- `tests/`: automatic tests (`make test`).
- `AGENTS.md`, `GEMINI.md`: rules for AI assistants.
