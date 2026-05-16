#!/usr/bin/env python3
# SOURCE OF TRUTH: nix-config/scripts/gen-ansible-inventory.py
import json
import subprocess
import os

def main():
    # Find inventory.nix relative to the script location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    inventory_nix = os.path.join(script_dir, "..", "inventory.nix")
    
    try:
        result = subprocess.run(
            ["nix", "eval", "--json", "-f", inventory_nix],
            capture_output=True,
            text=True,
            check=True
        )
        inventory = json.loads(result.stdout)
    except Exception as e:
        print(f"Error evaluating inventory.nix: {e}")
        return

    hosts = inventory.get("hosts", {})
    
    # We want to group them for Ansible
    groups = {
        "mediatek": [],
        "routers": [],
        "gateways": [],
        "access_points": [],
        "brains": []
    }

    # Static vars for mediatek group (as seen in current inventory.ini)
    mediatek_vars = {
        "ansible_user": "root",
        "ansible_python_interpreter": "/usr/bin/python3",
        "wan_iface": "eth1",
        "lan_iface": "eth0"
    }

    lines = []
    lines.append("# Generated from nix-config/inventory.nix - DO NOT EDIT MANUALLY\n")

    # Grouping logic
    for name, data in hosts.items():
        tags = data.get("tags", [])
        ip = data.get("ip", "")
        
        if "physical" in tags:
            groups["mediatek"].append(f"{name} ansible_host={ip}")
            groups["routers"].append(name)
            if "gateway" in tags:
                groups["gateways"].append(name)
            if "lxc-host" in tags:
                groups["access_points"].append(name)
        
        if "brain" in tags:
            groups["brains"].append(f"{name} ansible_host={ip} ansible_user=root")

    # Write groups
    for group_name, members in groups.items():
        if not members:
            continue
        lines.append(f"[{group_name}]")
        for member in members:
            lines.append(member)
        
        # Add vars for mediatek
        if group_name == "mediatek":
            lines.append(f"\n[{group_name}:vars]")
            for k, v in mediatek_vars.items():
                lines.append(f"{k}={v}")
        
        lines.append("")

    # Output to stdout or file
    output = "\n".join(lines)
    print(output)

if __name__ == "__main__":
    main()
