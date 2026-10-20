#!/usr/bin/env python3
"""
Official Game Data Fetcher / Database updater for WoW Forever Leveler.
Abides strictly by Blizzard Terms of Service by using the official Blizzard Game Data API.
Fetches quest information, zones, and profession recipes to data/database.json.
"""

import os
import sys
import json
import base64
import urllib.request
import urllib.parse
import urllib.error

ENV_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '.env')
DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'data')

def load_env():
    env_vars = {}
    if not os.path.exists(ENV_PATH):
        print(f"[!] .env file not found at {ENV_PATH}")
        return None
    with open(ENV_PATH, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, val = line.split('=', 1)
                env_vars[key.strip()] = val.strip()
    return env_vars

def get_token(client_id, client_secret):
    url = "https://oauth.battle.net/token"
    auth_header = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    req = urllib.request.Request(
        url,
        data=b"grant_type=client_credentials",
        headers={
            "Authorization": f"Basic {auth_header}",
            "Content-Type": "application/x-www-form-urlencoded"
        }
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())["access_token"]
    except Exception as e:
        print(f"[!] Token error: {e}")
        return None

def fetch_endpoint(url, token):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return {"error": e.code, "url": url}
    except Exception as e:
        return {"error": str(e), "url": url}

def main():
    print("=================================================")
    print("   WoW Forever Official Game Data Updater")
    print("=================================================")
    
    env = load_env()
    if not env:
        sys.exit(1)
        
    client_id = env.get("BNET_CLIENT_ID")
    client_secret = env.get("BNET_CLIENT_SECRET")
    region = env.get("BNET_REGION", "eu").lower()
    
    token = get_token(client_id, client_secret)
    if not token:
        print("[!] Failed to obtain Blizzard API access token.")
        sys.exit(1)
        
    print("[+] Successfully authenticated with Blizzard Game Data API.")
    os.makedirs(DATA_DIR, exist_ok=True)
    
    namespace = f"static-classic1x-{region}"
    print(f"[*] Querying official index data for namespace '{namespace}'...")
    
    database = {
        "region": region,
        "namespace": namespace,
        "playable_classes": {},
        "playable_races": {},
        "professions": {}
    }
    
    # 1. Playable Classes
    classes_url = f"https://{region}.api.blizzard.com/data/wow/playable-class/index?namespace={namespace}&locale=en_US"
    classes_data = fetch_endpoint(classes_url, token)
    if "classes" in classes_data:
        database["playable_classes"] = classes_data["classes"]
        print(f"[+] Loaded {len(classes_data['classes'])} playable classes.")

    # 2. Playable Races
    races_url = f"https://{region}.api.blizzard.com/data/wow/playable-race/index?namespace={namespace}&locale=en_US"
    races_data = fetch_endpoint(races_url, token)
    if "races" in races_data:
        database["playable_races"] = races_data["races"]
        print(f"[+] Loaded {len(races_data['races'])} playable races.")

    # 3. Professions
    professions_url = f"https://{region}.api.blizzard.com/data/wow/profession/index?namespace={namespace}&locale=en_US"
    professions_data = fetch_endpoint(professions_url, token)
    if "professions" in professions_data:
        database["professions"] = professions_data["professions"]
        print(f"[+] Loaded {len(professions_data['professions'])} professions.")

    output_path = os.path.join(DATA_DIR, 'database.json')
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(database, f, indent=2)
        
    print(f"\n[+] Database updated successfully: {output_path}")

if __name__ == "__main__":
    main()
