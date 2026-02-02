#!/usr/bin/env python3
import toml
import subprocess
import os
import sys
import glob
import requests

# Paths
INPUT_DIR = "modules/home-manager/code-common/extensions"
OUTPUT_DIR = "modules/home-manager/code-common/extensions"

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
        "flags": 914
    }
    
    try:
        response = requests.post(url, headers=headers, json=data)
        response.raise_for_status()
        results = response.json()
        versions = results["results"][0]["extensions"][0]["versions"]
        return versions[0]["version"]
    except Exception as e:
        print(f"  ❌ Version check failed for {publisher}.{name}: {e}")
        return None

def fetch_extension(pub, name, version_override=None):
    if version_override:
        print(f"  📌 Pinning {pub}.{name} @ {version_override}...")
        version = version_override
    else:
        print(f"  🔍 Checking latest version for {pub}.{name}...")
        version = get_latest_version(pub, name)
    
    if not version:
        return None
        
    print(f"  📦 Fetching {pub}.{name} @ {version}...")
    
    url = f"https://marketplace.visualstudio.com/_apis/public/gallery/publishers/{pub}/vsextensions/{name}/{version}/vspackage"
    
    cmd = ["nix-prefetch-url", url, "--name", f"{pub}-{name}-{version}.zip"]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        sha256 = result.stdout.strip()
        if result.returncode != 0:
            print(f"  ❌ Prefetch failed: {result.stderr}")
            return None
        return f'''  {{
    name = "{name}";
    publisher = "{pub}";
    version = "{version}";
    sha256 = "{sha256}";
  }}'''
    except Exception as e:
        print(f"  ❌ Error: {e}")
        return None

def process_file(input_file):
    filename = os.path.basename(input_file)
    name_no_ext = os.path.splitext(filename)[0]
    output_file = os.path.join(OUTPUT_DIR, f"{name_no_ext}.nix")
    
    print(f"📄 Processing {filename} -> {name_no_ext}.nix ...")
    
    try:
        data = toml.load(input_file)
    except Exception as e:
        print(f"❌ Error parsing TOML {input_file}: {e}")
        return

    blocks = []
    for ext in data.get("extensions", []):
        # Check for explicit version pin
        version = ext.get("version")
        block = fetch_extension(ext["publisher"], ext["name"], version)
        if block:
            blocks.append(block)

    with open(output_file, "w") as f:
        f.write("{ pkgs }:\n\n")
        f.write("# ⚠️ GENERATED FILE - DO NOT EDIT MANUALLY\n")
        f.write(f"# Generated from {filename} by scripts/update_extensions.py\n\n")
        f.write("pkgs.vscode-utils.extensionsFromVscodeMarketplace [\n")
        f.write("\n".join(blocks))
        f.write("\n]\n")
    
    print(f"✅ Written {len(blocks)} extensions to {output_file}\n")

def main():
    if not os.path.exists(INPUT_DIR):
        print(f"❌ Error: {INPUT_DIR} not found.")
        sys.exit(1)

    files = glob.glob(os.path.join(INPUT_DIR, "*.toml"))
    if not files:
        print(f"❌ No TOML files found in {INPUT_DIR}")
        sys.exit(1)

    print(f"🚀 Found {len(files)} expansion configurations.\n")
    for f in files:
        process_file(f)

if __name__ == "__main__":
    main()
