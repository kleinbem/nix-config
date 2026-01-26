#!/usr/bin/env python3
import toml
import subprocess
import os
import sys
import requests
import json

# Paths
INPUT_FILE = "modules/home-manager/code-common/extensions.toml"
OUTPUT_FILE = "modules/home-manager/code-common/extensions.nix"

def get_latest_version(publisher, name):
    url = "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json;api-version=3.0-preview.1"
    }
    data = {
        "filters": [{
            "criteria": [
                {"filterType": 7, "value": f"{publisher}.{name}"}
            ]
        }],
        "flags": 914 # IncludeVersions, IncludeFiles, etc.
    }
    # Flags: 0x200 (Latest Version only?)
    # Actually just defaults work usually.
    
    try:
        response = requests.post(url, headers=headers, json=data)
        response.raise_for_status()
        results = response.json()
        versions = results["results"][0]["extensions"][0]["versions"]
        return versions[0]["version"]
    except Exception as e:
        print(f"❌ Version check failed for {publisher}.{name}: {e}")
        return None

def fetch_extension(pub, name):
    print(f"🔍 Checking latest version for {pub}.{name}...")
    version = get_latest_version(pub, name)
    if not version:
        return None
        
    print(f"📦 Fetching {pub}.{name} @ {version}...")
    
    url = f"https://marketplace.visualstudio.com/_apis/public/gallery/publishers/{pub}/vsextensions/{name}/{version}/vspackage"
    name_snake = name.replace("-", "_") # Nix cleaner name handling?
    
    # nix-prefetch-url url --name ...
    # We let nix calculate the hash
    cmd = ["nix-prefetch-url", url, "--name", f"{pub}-{name}-{version}.zip"]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        sha256 = result.stdout.strip()
        if result.returncode != 0:
            print(f"❌ Prefetch failed: {result.stderr}")
            return None
        return f'''  {{
    name = "{name}";
    publisher = "{pub}";
    version = "{version}";
    sha256 = "{sha256}";
  }}'''
    except Exception as e:
        print(f"❌ Error: {e}")
        return None

def main():
    if not os.path.exists(INPUT_FILE):
        print(f"❌ Error: {INPUT_FILE} not found.")
        sys.exit(1)

    print(f"🔄 Reading {INPUT_FILE}...")
    try:
        data = toml.load(INPUT_FILE)
    except Exception as e:
        print(f"❌ Error parsing TOML: {e}")
        sys.exit(1)

    with open(OUTPUT_FILE, "w") as f:
        f.write("{ pkgs }:\n\n")
        f.write("# ⚠️ GENERATED FILE - DO NOT EDIT MANUALLY\n")
        f.write("# Edit extensions.toml and run 'just update-extensions' instead.\n\n")
        f.write("pkgs.vscode-utils.extensionsFromVscodeMarketplace [\n")
        
        for ext in data.get("extensions", []):
            block = fetch_extension(ext["publisher"], ext["name"])
            if block:
                f.write(block + "\n")
                
        f.write("]\n")
    
    print(f"✅ Success! Written to {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
