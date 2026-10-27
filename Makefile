.PHONY: help serve sync roster refresh scan gamedata check addon guide quests routes test launch-check live

WOW_ROOT ?= /Applications/World of Warcraft

help:
	@echo "make serve     Start the dashboard on http://localhost:8765/"
	@echo "make refresh   Log in to Battle.net, sync characters, rebuild the dashboard roster"
	@echo "make sync      Log in to Battle.net and sync characters only"
	@echo "make roster    Rebuild personal/roster.js from the last sync"
	@echo "make guide     Rebuild guide.md and data/guide.js from data/guide.json"
	@echo "make routes    Quest routes per zone (recorded journeys + QuestieDB), then make guide"
	@echo "make quests    Compare your addon quest log with the guide (personal/quest_report.md)"
	@echo "make test      Run the automatic tests (dashboard math and sync scripts)"
	@echo "make launch-check  Check game folders, addon, save files, Blizzard API and tests"
	@echo "make scan      Scan the local WoW folder for characters"
	@echo "make gamedata  Fetch classes, races and professions from the Blizzard API"
	@echo "make check     Test the Battle.net API credentials in .env"
	@echo "make addon     Install the in-game addon into every local WoW client (beta, classic, ...)"
	@echo "make live      Set up the live client: copy missing addons from the beta, install ours, import settings"

serve:
	./scripts/serve.sh

sync:
	python3 scripts/sync_characters.py

roster:
	python3 scripts/build_roster.py

guide:
	python3 scripts/refresh_data.py
	python3 scripts/build_guide.py

quests:
	python3 scripts/quest_report.py

routes:
	python3 scripts/build_routes.py
	python3 scripts/build_guide.py

refresh: sync roster guide quests

scan:
	python3 scripts/scan_local_wow.py

gamedata:
	python3 scripts/scraper.py

check:
	python3 scripts/test_bnet.py

addon: guide
	@cp addon/WoWForeverLeveler_Planner/Alert.lua addon/WoWForeverLeveler_ClassicTest/Alert.lua
	@for flavor in "$(WOW_ROOT)"/_*_; do \
		[ -d "$$flavor" ] || continue; \
		case "$$flavor" in *_classic_era_|*_anniversary_|*_classic_) classic=1 ;; *) classic=0 ;; esac; \
		for a in addon/*/; do \
			name=$$(basename "$$a"); \
			if [ "$$name" = WoWForeverLeveler_ClassicTest ]; then [ $$classic = 1 ] || continue; else [ $$classic = 0 ] || continue; fi; \
			mkdir -p "$$flavor/Interface/AddOns/$$name"; \
			cp -R "$$a"* "$$flavor/Interface/AddOns/$$name/"; \
		done; \
		echo "Installed into $$flavor"; \
	done
	@echo "Type /reload in game or log in again."

test: guide
	node --test tests/
	python3 -m unittest discover -s tests

launch-check:
	python3 scripts/launch_check.py

live:
	python3 scripts/live_setup.py
