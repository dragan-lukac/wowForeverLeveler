#!/usr/bin/env python3
"""
Scans the local World of Warcraft installation on macOS for accounts, realms, and characters.
Parses both live Classic and Classic Beta installations.
"""

import os
import sys
import json
import glob

POSSIBLE_WOW_PATHS = [
    "/Applications/World of Warcraft",
    os.path.expanduser("~/Applications/World of Warcraft"),
    "/Users/Shared/Battle.net"
]

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'data')
PERSONAL_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'personal')  # personal, not in git

def find_wtf_folders():
    wtf_paths = []
    for base in POSSIBLE_WOW_PATHS:
        if os.path.exists(base):
            for flavor in ["_classic_beta_", "_classic_", "_classic_era_", "_retail_"]:
                p = os.path.join(base, flavor, "WTF", "Account")
                if os.path.exists(p):
                    wtf_paths.append((flavor.strip('_'), p))
    return wtf_paths

def scan_local_characters():
    results = {}
    wtf_folders = find_wtf_folders()
    
    for flavor, account_dir in wtf_folders:
        for acc in os.listdir(account_dir):
            acc_path = os.path.join(account_dir, acc)
            if not os.path.isdir(acc_path) or acc == "SavedVariables":
                continue
                
            # Each subdirectory inside an account folder that isn't SavedVariables is a realm!
            for realm in os.listdir(acc_path):
                realm_path = os.path.join(acc_path, realm)
                if not os.path.isdir(realm_path) or realm == "SavedVariables":
                    continue
                    
                realm_key = f"{realm} ({flavor})"
                if realm_key not in results:
                    results[realm_key] = {
                        "realm": realm,
                        "flavor": flavor,
                        "account": acc,
                        "characters": []
                    }
                    
                for char in os.listdir(realm_path):
                    char_path = os.path.join(realm_path, char)
                    if os.path.isdir(char_path):
                        # Attempt to inspect char files
                        addons_file = os.path.join(char_path, "AddOns.txt")
                        results[realm_key]["characters"].append({
                            "name": char,
                            "realm": realm,
                            "flavor": flavor,
                            "account": acc,
                            "path": char_path
                        })
                        
    os.makedirs(PERSONAL_DIR, exist_ok=True)
    out_file = os.path.join(PERSONAL_DIR, 'local_characters.json')
    with open(out_file, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2)
        
    print(f"[+] Found {len(results)} local realms across your WoW installations.")
    for r_key, r_info in results.items():
        print(f"  - [{r_key}] ({len(r_info['characters'])} characters):")
        for c in r_info['characters']:
            print(f"      • {c['name']}")
            
    print(f"\n[+] Local character scan saved to: {out_file}")
    return results

if __name__ == "__main__":
    scan_local_characters()
