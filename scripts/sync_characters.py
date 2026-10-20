#!/usr/bin/env python3
"""
Interactive OAuth flow to fetch characters from Battle.net Profile API.
Starts a temporary local server on localhost:8000 to catch the OAuth callback.
"""

import os
import sys
import json
import base64
import urllib.request
import urllib.parse
import urllib.error
import webbrowser
from http.server import HTTPServer, BaseHTTPRequestHandler

ENV_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '.env')
DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'data')
PERSONAL_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'personal')  # your account's characters: personal, not in git

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

env = load_env()
if not env:
    sys.exit(1)

CLIENT_ID = env.get("BNET_CLIENT_ID")
CLIENT_SECRET = env.get("BNET_CLIENT_SECRET")
REGION = env.get("BNET_REGION", "eu").lower()
REDIRECT_URI = env.get("BNET_REDIRECT_URI", "http://localhost:8000/callback")
PORT = 8000

auth_code = None

def exchange_code_for_token(code):
    url = "https://oauth.battle.net/token"
    auth_header = base64.b64encode(f"{CLIENT_ID}:{CLIENT_SECRET}".encode()).decode()
    data = urllib.parse.urlencode({
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': REDIRECT_URI
    }).encode()
    
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
    except Exception as e:
        print(f"[!] Error exchanging code for token: {e}")
        return None

def fetch_characters(user_token):
    os.makedirs(PERSONAL_DIR, exist_ok=True)
    results = {}
    
    # Check both Classic and Main/Beta profile namespaces
    namespaces = [
        f"profile-classic-{REGION}",
        f"profile-classic1x-{REGION}",
        f"profile-{REGION}"
    ]
    
    for ns in namespaces:
        url = f"https://{REGION}.api.blizzard.com/profile/user/wow?namespace={ns}&locale=en_US"
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {user_token}"})
        try:
            with urllib.request.urlopen(req) as resp:
                data = json.loads(resp.read().decode())
                results[ns] = data
                print(f"[+] Successfully queried namespace: {ns}")
        except urllib.error.HTTPError as e:
            print(f"[-] Namespace {ns}: HTTP {e.code}")
        except Exception as e:
            print(f"[-] Namespace {ns}: {e}")
            
    output_path = os.path.join(PERSONAL_DIR, 'account_characters.json')
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2)
    print(f"\n[+] Character profile data saved to: {output_path}")
    return results

import secrets

STATE = secrets.token_hex(16)

class OAuthCallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global auth_code
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        
        if parsed.path == '/callback':
            returned_state = params.get('state', [None])[0]
            if returned_state != STATE:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Error: State parameter mismatch or missing.")
                return

            if 'code' in params:
                auth_code = params['code'][0]
                self.send_response(200)
                self.send_header('Content-type', 'text/html; charset=utf-8')
                self.end_headers()
                self.wfile.write(b"""
                <html>
                <body style="font-family: sans-serif; background: #0f172a; color: #f8fafc; padding: 40px; text-align: center;">
                    <h2 style="color: #22c55e;">&#10004; Battle.net Authorization Successful!</h2>
                    <p>You can close this tab and return to your Antigravity session.</p>
                </body>
                </html>
                """)
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Error: Missing auth code.")
        else:
            self.send_response(404)
            self.end_headers()

def main():
    auth_url = (
        f"https://oauth.battle.net/authorize?"
        f"client_id={CLIENT_ID}&"
        f"scope=wow.profile&"
        f"state={STATE}&"
        f"response_type=code&"
        f"redirect_uri={urllib.parse.quote(REDIRECT_URI)}"
    )
    
    print("\n=======================================================")
    print("   Battle.net Character Synchronization (OAuth Flow)")
    print("=======================================================\n")
    print("To authorize access to your WoW characters, please open:")
    print(f"\n{auth_url}\n")
    
    # Try opening browser automatically on Mac
    try:
        webbrowser.open(auth_url)
    except Exception:
        pass
        
    print("[*] Waiting for OAuth callback on http://localhost:8000/callback...")
    server = HTTPServer(('localhost', PORT), OAuthCallbackHandler)
    server.timeout = 120
    
    while not auth_code:
        server.handle_request()
        
    print("\n[+] Authorization code received from Battle.net!")
    print("[*] Exchanging code for user profile token...")
    user_token = exchange_code_for_token(auth_code)
    
    if not user_token:
        print("[!] Failed to obtain user token.")
        sys.exit(1)
        
    print("[+] User token obtained! Querying character profile endpoints...")
    data = fetch_characters(user_token)
    
    # Print summary of found characters
    print("\n--- Summary of Found Characters ---")
    found_any = False
    for ns, res in data.items():
        accounts = res.get("wow_accounts", [])
        for acc in accounts:
            chars = acc.get("characters", [])
            for c in chars:
                found_any = True
                name = c.get("name")
                lvl = c.get("level")
                cls_name = c.get("playable_class", {}).get("name", "Unknown")
                realm = c.get("realm", {}).get("name", "Unknown")
                print(f" - [{realm}] {name} - Level {lvl} {cls_name} (Namespace: {ns})")
                
    if not found_any:
        print("[i] Note: No characters returned in these namespaces, or the character has not logged out yet since creation.")

if __name__ == "__main__":
    main()
