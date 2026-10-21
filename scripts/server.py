#!/usr/bin/env python3
"""
Dashboard server on http://localhost:8765/.
Serves the project files and exposes POST /api/sync (Sync buttons) and POST /api/plan
(profession picker, writes personal/team.json) for index.html.
Port 8000 stays free for the Battle.net OAuth callback in sync_characters.py.
"""

import os
import sys
import glob
import json
import time
import threading
import subprocess
from functools import partial
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOST, PORT = "127.0.0.1", 8765
ALLOWED_HOSTS = {f"localhost:{PORT}", f"127.0.0.1:{PORT}"}
BNET_TIMEOUT = 180
GUIDE_JSON = os.path.join(ROOT, "data", "guide.json")
sync_lock = threading.Lock()
LAST_SYNC_FILE = os.path.join(ROOT, "data", ".last_sync.json")
SAVE_WAIT = 60   # seconds a sync waits for the game to write its save file
SAVE_SETTLE = 2  # the file must stay unchanged this long before it is read


def save_file_mtime():
    """Newest write time of any addon save file, or 0 when there is none."""
    from build_roster import WOW_ROOTS
    pattern = "WTF/Account/*/SavedVariables/WoWForeverLeveler.lua"
    paths = [p for root in WOW_ROOTS for p in glob.glob(os.path.join(root, "_*_", pattern))]
    return max((os.path.getmtime(p) for p in paths), default=0)


def game_running():
    return subprocess.run(["pgrep", "-f", "World of Warcraft.*/MacOS/World of Warcraft"],
                          capture_output=True).returncode == 0


def wait_for_save(last_synced, mtime=save_file_mtime, running=game_running,
                  timeout=SAVE_WAIT, settle=SAVE_SETTLE, sleep=time.sleep):
    """After /reload the game writes its save file a few seconds later. When the game runs and the
    file has not changed since the last sync, wait for the new file (up to `timeout` seconds).
    Returns a note for the sync log, or "" when no wait was needed."""
    if mtime() > last_synced or not running():
        return ""
    waited = 0
    while waited < timeout:
        sleep(1)
        waited += 1
        if mtime() > last_synced:
            seen = mtime()
            sleep(settle)
            while mtime() != seen:  # still being written
                seen = mtime()
                sleep(settle)
            return f"Waited {waited} s for the game to save."
    return f"The game did not save within {timeout} s. Did you /reload or log out? Synced the old save file."


def read_last_sync():
    try:
        with open(LAST_SYNC_FILE, encoding="utf-8") as f:
            return json.load(f).get("saveFileMtime", 0)
    except (OSError, ValueError):
        return 0


def write_last_sync(mtime):
    with open(LAST_SYNC_FILE, "w", encoding="utf-8") as f:
        json.dump({"saveFileMtime": mtime}, f)


def run_script(name, timeout):
    proc = subprocess.run(
        [sys.executable, os.path.join(ROOT, "scripts", name)],
        cwd=ROOT, capture_output=True, text=True, timeout=timeout,
    )
    return proc.returncode, (proc.stdout + proc.stderr).strip()


# refresh_data.py: the QuestieDB-built files (dungeon givers, vendors) stay current after an addon update.
SYNC_SCRIPTS = ("build_roster.py", "quest_report.py", "build_routes.py", "refresh_data.py", "build_guide.py")
WATCH_EVERY = 5  # seconds between checks of the save file


def run_sync_scripts():
    """Rebuilds the dashboard data from the save files. Returns (ok, log)."""
    ok, logs = True, []
    for script in SYNC_SCRIPTS:
        code, out = run_script(script, 60)
        logs.append(out)
        ok = ok and code == 0
    return ok, "\n".join(logs)


def watch_save_file(mtime=save_file_mtime, now=time.time, sleep=time.sleep, once=False):
    """Auto sync: when the game writes a new save file (/reload, logout, or the addon's Sync menu), rebuild the
    dashboard data without a click. Waits until the file has been unchanged for SAVE_SETTLE seconds."""
    while True:
        latest = mtime()
        if latest > read_last_sync() and now() - latest >= SAVE_SETTLE and sync_lock.acquire(blocking=False):
            try:
                ok, log = run_sync_scripts()
                if ok:
                    write_last_sync(latest)
                print(f"[auto sync] {'done' if ok else 'failed'} ({time.strftime('%H:%M:%S')})" + ("" if ok else "\n" + log))
            finally:
                sync_lock.release()
        if once:
            return
        sleep(WATCH_EVERY)


class DashboardHandler(SimpleHTTPRequestHandler):
    def host_ok(self):
        # Blocks DNS-rebinding pages from reaching this server under another hostname.
        return self.headers.get("Host") in ALLOWED_HOSTS

    def do_GET(self):
        if not self.host_ok():
            return self.send_error(403)
        if any(part.startswith(".") for part in self.path.split("?")[0].split("/")):
            return self.send_error(404)
        super().do_GET()

    def do_POST(self):
        # The custom header forces a CORS preflight, so other websites cannot trigger a sync.
        if not self.host_ok() or self.headers.get("X-Requested-With") != "dashboard":
            return self.send_error(403)
        route = self.path.split("?")[0]
        if route not in ("/api/sync", "/api/plan"):
            return self.send_error(404)
        if not sync_lock.acquire(blocking=False):
            return self.send_json(409, {"ok": False, "log": "A sync is already running."})
        try:
            if route == "/api/plan":
                return self.save_plan()
            use_bnet = "bnet=1" in self.path
            logs = []
            if use_bnet:
                try:
                    code, out = run_script("sync_characters.py", BNET_TIMEOUT)
                except subprocess.TimeoutExpired:
                    return self.send_json(504, {"ok": False, "log": "Battle.net login timed out. Try again."})
                logs.append(out)
                if code != 0:
                    return self.send_json(500, {"ok": False, "log": "\n".join(logs)})
            logs.append(wait_for_save(read_last_sync()))
            synced_mtime = save_file_mtime()
            ok, log = run_sync_scripts()
            logs.append(log)
            if ok:
                write_last_sync(synced_mtime)
            self.send_json(200 if ok else 500, {"ok": ok, "log": "\n".join(logs)})
        finally:
            sync_lock.release()

    def save_plan(self):
        try:
            length = min(int(self.headers.get("Content-Length", 0)), 10_000)
            req = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return self.send_json(400, {"ok": False, "log": "Bad request body."})

        from team import load_guide, save_character
        guide = load_guide()
        profs = req.get("profs")
        race = req.get("race")
        char = next((c for c in guide["characters"] if c["id"] == req.get("id")), None)
        primary = {code for code, p in guide["professions"].items() if p.get("type") in ("gather", "craft")}
        if (not char or not isinstance(profs, list) or len(profs) != 2 or len(set(profs)) != 2
                or any(p not in primary for p in profs)):
            return self.send_json(400, {"ok": False, "log": "Need a known character and 2 different primary professions."})
        races = guide.get("races", {})
        if race is not None and (race not in races or char["class"] not in races[race]["classes"]):
            return self.send_json(400, {"ok": False, "log": f"A {race} cannot be a {char['class']}."})

        # Personal choices go to personal/team.json (the route's first zone follows the race on load).
        save_character(char["id"], profs=profs, **({"race": race} if race is not None else {}))
        code, out = run_script("build_guide.py", 60)
        self.send_json(200 if code == 0 else 500, {"ok": code == 0, "log": out})

    def send_json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    handler = partial(DashboardHandler, directory=ROOT)
    print(f"Dashboard: http://localhost:{PORT}/")
    threading.Thread(target=watch_save_file, daemon=True).start()
    ThreadingHTTPServer((HOST, PORT), handler).serve_forever()
