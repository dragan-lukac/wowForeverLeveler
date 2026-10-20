#!/usr/bin/env python3
"""
Test Battle.net API connectivity and explore available realms/namespaces.
Uses standard library urllib (no pip install required).
"""

import os
import sys
import json
import base64
import urllib.request
import urllib.parse
import urllib.error

ENV_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '.env')

def load_env():
    env_vars = {}
    if not os.path.exists(ENV_PATH):
        print(f"[!] .env file not found at {ENV_PATH}")
        print("    Please create a .env file with BNET_CLIENT_ID and BNET_CLIENT_SECRET.")
        return None
    with open(ENV_PATH, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, val = line.split('=', 1)
                env_vars[key.strip()] = val.strip()
    return env_vars

def get_access_token(client_id, client_secret):
    url = "https://oauth.battle.net/token"
    auth_header = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    data = urllib.parse.urlencode({'grant_type': 'client_credentials'}).encode()
    
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Basic {auth_header}",
            "Content-Type": "application/x-www-form-urlencoded"
        }
    )
    try:
        with urllib.request.urlopen(req) as resp:
            body = json.loads(resp.read().decode())
            return body.get("access_token")
    except urllib.error.HTTPError as e:
        print(f"[ERROR] Failed to fetch access token: HTTP {e.code} - {e.read().decode()}")
        return None
    except Exception as e:
        print(f"[ERROR] Network error: {e}")
        return None

def test_classic_realms(token, region="eu"):
    """Check classic realms index to see available realms/namespaces"""
    print(f"\n[*] Testing Classic Connected Realms index for region '{region}'...")
    namespaces = [
        f"dynamic-classic-{region}",
        f"dynamic-classic1x-{region}",
        f"dynamic-{region}"
    ]
    
    for ns in namespaces:
        url = f"https://{region}.api.blizzard.com/data/wow/connected-realm/index?namespace={ns}&locale=en_US"
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
        try:
            with urllib.request.urlopen(req) as resp:
                data = json.loads(resp.read().decode())
                realms = data.get("connected_realms", [])
                print(f"[+] Namespace '{ns}' SUCCESS! Found {len(realms)} connected realm clusters.")
                return ns
        except urllib.error.HTTPError as e:
            print(f"[-] Namespace '{ns}': HTTP {e.code}")
        except Exception as e:
            print(f"[-] Namespace '{ns}': {e}")
    return None

def main():
    print("========================================")
    print("   Blizzard Battle.net API Checker")
    print("========================================")
    env = load_env()
    if not env:
        sys.exit(1)
        
    client_id = env.get("BNET_CLIENT_ID")
    client_secret = env.get("BNET_CLIENT_SECRET")
    region = env.get("BNET_REGION", "eu").lower()
    
    if not client_id or not client_secret or "your_client_" in client_id:
        print("[!] Missing valid BNET_CLIENT_ID or BNET_CLIENT_SECRET in .env.")
        print(f"    Open {ENV_PATH} and set your credentials.")
        sys.exit(1)
        
    print(f"[*] Authenticating with Blizzard OAuth ({region.upper()})...")
    token = get_access_token(client_id, client_secret)
    if not token:
        print("[!] Authentication failed. Check your Client ID and Client Secret.")
        sys.exit(1)
        
    print(f"[+] Access token successfully acquired! (length: {len(token)})")
    test_classic_realms(token, region)
    print("\n[+] Battle.net API connection verified successfully!")

if __name__ == "__main__":
    main()
