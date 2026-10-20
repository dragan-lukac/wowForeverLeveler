#!/bin/sh
# Port 8000 is reserved for the Battle.net OAuth callback in sync_characters.py.
cd "$(dirname "$0")/.." || exit 1
exec python3 scripts/server.py
