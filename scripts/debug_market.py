import requests
import json
import sys
import argparse

def search_marketplace(query, use_openvsx=False):
    if use_openvsx:
        url = "https://open-vsx.org/api/-/search"
        print(f"Searching Open VSX for '{query}'...")
        params = {"query": query, "size": 10}
        try:
            response = requests.get(url, params=params)
            response.raise_for_status()
            results = response.json()
            
            if not results.get("extensions"):
                print("No extensions found on Open VSX.")
                return

            for e in results["extensions"]:
                namespace = e.get("namespace", "Unknown")
                name = e.get("name", "Unknown")
                display_name = e.get("displayName", "No display name")
                version = e.get("version", "Unknown")
                
                print(f"ID: {namespace}.{name}")
                print(f"Name: {display_name}")
                print(f"Version: {version}")
                print("-" * 20)
                
        except Exception as e:
            print(f"Error querying Open VSX: {e}")
            
    else:
        url = "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"
        print(f"Searching VS Code Marketplace for '{query}'...")
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json;api-version=3.0-preview.1"
        }
        data = {
            "filters": [{
                "criteria": [
                    {"filterType": 10, "value": query} 
                ]
            }],
            "flags": 914
        }

        try:
            response = requests.post(url, headers=headers, json=data)
            response.raise_for_status()
            results = response.json()
            
            if not results["results"] or not results["results"][0].get("extensions"):
                print("No extensions found on VS Code Marketplace.")
                return

            exts = results["results"][0]["extensions"]
            for e in exts:
                publisher = e.get("publisher", {}).get("publisherName", "Unknown")
                name = e.get("extensionName", "Unknown")
                display_name = e.get("displayName", "No display name")
                version = e["versions"][0]["version"] if e.get("versions") else "Unknown"
                
                print(f"ID: {publisher}.{name}")
                print(f"Name: {display_name}")
                print(f"Version: {version}")
                print("-" * 20)
                
        except Exception as e:
            print(f"Error querying VS Code Marketplace: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Search VS Code Marketplace or Open VSX for extensions.")
    parser.add_argument("query", help="Search term (e.g., publisher name, extension name, or keyword)")
    parser.add_argument("--openvsx", action="store_true", help="Search Open VSX Registry instead of VS Code Marketplace")
    
    args = parser.parse_args()
    search_marketplace(args.query, args.openvsx)
