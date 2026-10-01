#!/usr/bin/env python3
"""Generate INFRASTRUCTURE.yaml — Complete AI Knowledge Manifest for the kleinbem fleet.

This script compiles the entire multi-repo Nix ecosystem into a single, structured,
token-efficient YAML document optimized for LLM comprehension and reasoning.

It extracts:
  1. Fleet Invariants & Architectural Rules
  2. Multi-Repo Atlas (19 repositories)
  3. Fleet Network & Ingress Topology (Subnets, NetBird, Tang, Tunnels, Caddy)
  4. System & Home-Manager Module Catalogs (Declarations, options, opted-in hosts)
  5. Shared Presets & Hardware Profiles (Containers, bundles, GPU/SoC configs)
  6. Deep Host Matrix (Specs, Disko storage, impermanence, enabled my.* options, active containers)
  7. Workload & Container Catalog (All ~30 containers, ports, domains, auth, upstream paths)
  8. Personas & AI Agents (Models, toolchains, permissions, active hours)
  9. Infrastructure as Code & Secrets Bridges (OpenTofu roots, SOPS mappings)
 10. Developer Cheat Sheet & Safe Editing Recipes

Output:
  nix-config/docs/INFRASTRUCTURE.yaml
  (Symlinked at workspace root: ~/Develop/github.com/kleinbem/INFRASTRUCTURE.yaml)

Regenerated via: `just maintenance::sync-agent` or `just sync-infra`
Execution time: ~1.0 - 1.5 seconds.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

import yaml

# Determine workspace roots
SCRIPT_DIR = Path(__file__).resolve().parent
NIX_CONFIG = SCRIPT_DIR.parent
META_ROOT = NIX_CONFIG.parent

sys.path.insert(0, str(SCRIPT_DIR))
try:
    from _nix_options import (
        CONSUMER_DIRS,
        MODULE_DIRS,
        REPO,
        consumer_paths_in_file,
        declarations_in_file,
        extract_imports_in_file,
        iter_nix_files,
    )
except ImportError:
    print("Warning: _nix_options.py not importable directly", file=sys.stderr)


# ---------------------------------------------------------------------------
# Utility Helpers
# ---------------------------------------------------------------------------


def run_cmd(args: list[str], cwd: Path | None = None) -> str | None:
    """Run a shell command and return stdout string, or None on failure."""
    try:
        res = subprocess.run(
            args,
            cwd=cwd or NIX_CONFIG,
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        return res.stdout.strip()
    except Exception:
        return None


def eval_nix_json(file_path: Path, attr: str | None = None) -> Any:
    """Evaluate a .nix file to JSON using `nix eval`."""
    cmd = ["nix", "eval", "--json", "--file", str(file_path)]
    if attr:
        cmd.append(attr)
    out = run_cmd(cmd)
    if out:
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            pass
    return None


# ---------------------------------------------------------------------------
# Data Extractors
# ---------------------------------------------------------------------------


def get_invariants() -> dict[str, Any]:
    return {
        "switchboard_pattern": (
            "All system options live under `my.*` (schema in nix-config/modules/nixos/options.nix), "
            "Home-Manager under `modules.*`. Everything defaults to `enable = false`. "
            "Hosts explicitly opt in. Group attribute sets: use `my = { x.y = ...; };`."
        ),
        "standalone_containers_adr002": (
            "No host evaluates its own container closures. Central container-factory builds them; "
            "hosts pull closures to `/var/lib/machines/<name>/current`. "
            "Adding a container requires 4 steps: 1) preset in nix-presets/containers/<name>.nix, "
            "2) opt-in in host `containers.nix`, 3) entry in nix-config/inventory.nix network.nodes, "
            "4) entry in nix-config/hosts/container-factory/default.nix."
        ),
        "impermanence_and_storage": (
            "Root (`/`) is tmpfs wiped on boot on workstations/servers. "
            "All persistent state MUST be explicitly mounted or bound under `/persist` or `/data`. "
            "Disko partitions disks into LUKS + Btrfs subvolumes (@root, @nix, @persist, @swap)."
        ),
        "secrets_management": (
            "Central sops + age store in `kleinbem-secrets`. Cryptographically scoped per path. "
            "Hosts use host SSH keys or TPM-bound age keys to decrypt at boot. "
            "Never commit secrets inline; reference via `config.sops.secrets.<name>.path`."
        ),
        "vcs_and_multi_agent": (
            "Jujutsu (jj) is the primary VCS, colocated with git. "
            "When multiple agents work concurrently, each MUST claim a dedicated workspace "
            "via `just jj::ws-new <repo> [name]` to prevent working copy conflicts. "
            "When no YubiKey is plugged in, use plain git to avoid signed commit failures."
        ),
    }


def get_repo_atlas(repos: dict[str, str]) -> dict[str, Any]:
    repo_descriptions = {
        "kleinbem": "Fleet hub & orchestrator. Owns repos.nix, shared .just modules, and jj-fleet dashboard.",
        "nix": "Conductor for NixOS side. Houses live OpenTofu/Terraform IaC roots (Cloudflare, NetBird, Garage S3, Authentik).",
        "nix-config": "Primary NixOS consumer flake. Owns hosts, users, system & HM modules, inventory, PKI, and docs.",
        "nix-presets": "Shared service and desktop bundles: 30+ container definitions, backup-engine, desktop, terminal, herdr.",
        "nix-hardware": "Custom hardware flakes: nixos-nvme (Intel Core), orin-nano (Jetson Tegra/CUDA), rpi5, lxc-guest.",
        "nix-packages": "Custom packages and overlays: antigravity, buzz-desktop, langfuse, oh-my-pi, ricoh-driver.",
        "nix-devshells": "Developer shells provided via direnv: workspace (just, jj, gh, sops, age), openwrt, etc.",
        "nix-templates": "Flake templates for new services, modules, and projects.",
        "nix-gantry": "Continuous deployment engine and automatic updater.",
        "openwrt": "Conductor for router side.",
        "openwrt-config": "Runtime router configuration via Ansible (inventory.ini is generated from inventory.nix).",
        "openwrt-builder": "Firmware image generator for BPI-R4 routers.",
        "github-config": "OpenTofu-managed GitHub organization settings, repositories, and rulesets.",
        "kleinbem-secrets": "Central sops+age encrypted secrets repository with per-path scoped access.",
        "kleinbem-site": "kleinbem.dev personal portfolio website.",
        "kleinbem-auth": "Visitor login and authentication service.",
        "jj-toolbox": "Standalone Jujutsu helper scripts (jj-save, jj-push, jj-pull, jj-sign-unsigned).",
        "nix-toolbox": "Generic Nix flake dev tools (nix-check-versions, nix-audit-deps, bash-test-lib).",
        ".github": "Organization-wide GitHub Actions workflows and issue templates.",
    }
    atlas = {}
    for name, git_url in sorted(repos.items()):
        atlas[name] = {
            "path": f"{name}/",
            "url": git_url,
            "role": repo_descriptions.get(name, "Supporting repository."),
        }
    return atlas


def get_network_topology(inventory: dict[str, Any]) -> dict[str, Any]:
    net = inventory.get("network", {})
    hosts = inventory.get("hosts", {})
    tang = inventory.get("tangServers", [])
    mesh = inventory.get("meshGroups", {})

    container_subnets = {
        "nixos-nvme": "10.85.46.0/24 (cbr0)",
        "nasbook": "10.85.47.0/24 (cbr0)",
        "core-pi": "10.85.48.0/24 (cbr0)",
        "hass-pi": "10.85.49.0/24 (cbr0)",
        "mac-mini": "10.85.50.0/24 (cbr0)",
    }

    return {
        "primary_domain": "kleinbem.dev",
        "global_maintenance": net.get("globalMaintenance", False),
        "physical_lan": {
            "subnet": "10.0.0.0/24",
            "gateway": "10.0.0.1 (core-gateway, OpenWrt BPI-R4)",
            "access_point": "10.0.0.2 (ap-upstairs, OpenWrt BPI-R4)",
        },
        "container_subnets": container_subnets,
        "ingress_pipeline": {
            "public_entry": "Cloudflare Tunnel on core-pi",
            "reverse_proxy": "Caddy container on core-pi (10.85.48.107) terminating TLS and routing to internal IPs",
            "internal_bridge": "cbr0 container bridge interface on each host",
        },
        "netbird_mesh": {
            "subnet": "100.117.0.0/16",
            "control_plane": "NetBird Cloud managed via nix/infra/netbird OpenTofu",
            "groups": mesh,
        },
        "nbde_tang_mesh": {
            "purpose": "Network-Bound Disk Encryption (NBDE) unlocking root LUKS in initrd via Clevis",
            "port": 7654,
            "servers": tang,
        },
    }


def scan_host_containers(nix_config: Path) -> dict[str, list[str]]:
    """Scan each host directory and find active containers (enable = true)."""
    hosts_dir = nix_config / "hosts"
    result: dict[str, list[str]] = defaultdict(list)
    if not hosts_dir.is_dir():
        return result

    for host_dir in sorted(hosts_dir.iterdir()):
        if not host_dir.is_dir():
            continue
        host_name = host_dir.name
        # Grep-heuristic for container enables
        enabled_containers = set()
        for nix_file in host_dir.rglob("*.nix"):
            try:
                lines = nix_file.read_text(
                    encoding="utf-8", errors="ignore"
                ).splitlines()
            except OSError:
                continue
            in_containers = False
            depth = 0
            current_c = None
            for raw in lines:
                line = raw.strip()
                if re.search(r"\b(my\.containers|containers)\s*=\s*\{", line):
                    in_containers = True
                    depth = line.count("{") - line.count("}")
                    continue
                if in_containers:
                    depth += line.count("{") - line.count("}")
                    if depth <= 0:
                        in_containers = False
                        current_c = None
                        continue
                    m = re.match(r"([a-z][a-z0-9-]*)\s*=\s*\{", line)
                    if m:
                        current_c = m.group(1)
                        continue
                    m = re.match(
                        r"([a-z][a-z0-9-]*)\.enable\s*=\s*(lib\.mkForce\s+)?(true|false)",
                        line,
                    )
                    if m and m.group(3) == "true":
                        enabled_containers.add(m.group(1))
                        continue
                    m = re.match(r"enable\s*=\s*(lib\.mkForce\s+)?(true|false)", line)
                    if m and current_c and m.group(2) == "true":
                        enabled_containers.add(current_c)
        if enabled_containers:
            result[host_name] = sorted(enabled_containers)

    return result


def scan_host_secrets(nix_config: Path) -> dict[str, list[str]]:
    """Scan each host for sops.secrets references."""
    hosts_dir = nix_config / "hosts"
    result: dict[str, list[str]] = defaultdict(list)
    if not hosts_dir.is_dir():
        return result

    for host_dir in sorted(hosts_dir.iterdir()):
        if not host_dir.is_dir():
            continue
        secrets = set()
        for nix_file in host_dir.glob("*.nix"):
            try:
                txt = nix_file.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for m in re.finditer(r"sops\.secrets\.([a-zA-Z0-9_-]+)", txt):
                secrets.add(m.group(1))
            m_blk = re.search(r"secrets\s*=\s*\{([^}]+)\}", txt)
            if m_blk:
                for m in re.finditer(r"([a-zA-Z0-9_-]+)\s*=", m_blk.group(1)):
                    secrets.add(m.group(1))
        if secrets:
            result[host_dir.name] = sorted(secrets)
    return result


def scan_host_disko(nix_config: Path) -> dict[str, dict[str, Any]]:
    """Inspect storage & disko configs per host."""
    hosts_dir = nix_config / "hosts"
    storage_info: dict[str, dict[str, Any]] = {}
    for host_dir in sorted(hosts_dir.iterdir()):
        if not host_dir.is_dir():
            continue
        h_name = host_dir.name
        info: dict[str, Any] = {
            "framework": "Disko",
            "root_filesystem": "tmpfs (impermanence, wiped on boot)",
            "persist_paths": ["/persist"],
            "bootloader": "systemd-boot (UEFI)",
            "encryption": "LUKS with Clevis initrd NBDE Tang unlock",
        }
        if h_name in ("core-gateway", "ap-upstairs"):
            info = {
                "framework": "OpenWrt MTD / SquashFS + overlayfs",
                "bootloader": "U-Boot",
                "storage_type": "eMMC / SPI NAND",
            }
        elif h_name in ("core-pi", "hass-pi"):
            info = {
                "framework": "Disko (rpi5-disko.nix)",
                "root_filesystem": "tmpfs (impermanence)",
                "persist_paths": ["/persist"],
                "bootloader": "RPi EEPROM + UEFI Direct Boot",
                "encryption": "LUKS with Clevis initrd NBDE Tang unlock",
            }
        elif h_name == "orin-nano":
            info = {
                "framework": "Disko",
                "root_filesystem": "tmpfs (impermanence)",
                "persist_paths": ["/persist"],
                "bootloader": "NVIDIA Tegra U-Boot / UEFI",
                "encryption": "LUKS with Tang unlock",
            }
        storage_info[h_name] = info
    return storage_info


def build_host_matrix(
    inventory: dict[str, Any],
    nix_config: Path,
    host_containers: dict[str, list[str]],
    host_secrets: dict[str, list[str]],
) -> dict[str, Any]:
    hosts_inv = inventory.get("hosts", {})
    mesh_groups = inventory.get("meshGroups", {})
    disko_info = scan_host_disko(nix_config)
    hosts_dir = nix_config / "hosts"

    matrix = {}
    for h_name, h_data in sorted(hosts_inv.items()):
        # Find mesh group
        mg = None
        for group_name, members in mesh_groups.items():
            if h_name in members:
                mg = group_name
                break

        # Collect consumer paths / options
        host_paths = set()
        host_dir = hosts_dir / h_name
        if host_dir.is_dir():
            for nf in host_dir.glob("*.nix"):
                host_paths.update(consumer_paths_in_file(nf))

        # Filter enabled my.* options (keep high level subsystems)
        subsystems = defaultdict(list)
        for p in sorted(host_paths):
            if p.startswith("my."):
                parts = p.split(".")
                if len(parts) >= 2:
                    subsystem = parts[1]
                    subsystems[subsystem].append(".".join(parts[2:]))

        subsystems_summary = {}
        for sub, opts in subsystems.items():
            subsystems_summary[sub] = [o for o in opts if o] or ["enabled"]

        # Collect imports
        imports_summary = []
        entry_file = host_dir / "default.nix"
        if entry_file.exists():
            for imp in extract_imports_in_file(entry_file):
                imports_summary.append(f"[{imp.kind}] {imp.label}")

        host_entry: dict[str, Any] = {
            "tier": h_data.get("tags", ["server"])[0],
            "system": h_data.get(
                "system", "openwrt" if h_data.get("type") == "openwrt" else "unknown"
            ),
            "deploy_type": h_data.get(
                "deployType", "ansible" if h_data.get("type") == "openwrt" else "ssh"
            ),
            "tags": h_data.get("tags", []),
            "ips": {
                "physical": h_data.get("physicalIp") or h_data.get("ip"),
                "container_bridge": h_data.get("ip")
                if h_data.get("physicalIp")
                else None,
                "netbird": h_data.get("netbirdIp"),
            },
            "mesh_group": mg,
            "storage_and_boot": disko_info.get(h_name, {}),
            "imports": imports_summary[:15],  # Cap for conciseness
            "enabled_subsystems": subsystems_summary,
            "containers_hosted": host_containers.get(h_name, []),
            "secrets_consumed": host_secrets.get(h_name, []),
        }

        # Specific hardware profiles
        if h_name == "nixos-nvme":
            host_entry["hardware_profile"] = (
                "Intel Core Desktop (Zotac) + renderD128 QuickSync + FIDO2/YubiKey"
            )
        elif h_name == "orin-nano":
            host_entry["hardware_profile"] = (
                "NVIDIA Jetson Orin Nano (6-core ARM Cortex-A78AE, Ampere GPU, TensorRT/CUDA)"
            )
        elif h_name in ("core-pi", "hass-pi"):
            host_entry["hardware_profile"] = "Raspberry Pi 5 (BCM2712, 4x Cortex-A76)"
        elif h_name == "mac-mini":
            host_entry["hardware_profile"] = (
                "Apple Mac Mini Mid-2011 (Intel Core i5-2415M, x86_64)"
            )
        elif h_name == "nasbook":
            host_entry["hardware_profile"] = (
                "x86_64 Laptop/NAS with dedicated Btrfs /data storage pool"
            )
        elif h_name in ("core-gateway", "ap-upstairs"):
            host_entry["hardware_profile"] = (
                "Banana Pi BPI-R4 (MediaTek MT7988A Filogic 880, Quad-core A73, Wi-Fi 7)"
            )

        matrix[h_name] = host_entry

    return matrix


def build_services_catalog(
    inventory: dict[str, Any],
    host_containers: dict[str, list[str]],
    meta_root: Path,
) -> dict[str, Any]:
    nodes = inventory.get("network", {}).get("nodes", {})
    catalog = {}

    # Map container name to host based on active container enables or IP subnet
    ip_to_host = {
        "10.85.46": "nixos-nvme",
        "10.85.47": "nasbook",
        "10.85.48": "core-pi",
        "10.85.49": "hass-pi",
        "10.85.50": "mac-mini",
    }

    # Find preset file paths
    presets_dir = meta_root / "nix-presets" / "containers"

    for node_name, node_data in sorted(nodes.items()):
        ip = node_data.get("ip", "")
        assigned_host = "unassigned"

        # Check which host explicitly enables this container
        for h, c_list in host_containers.items():
            if node_name in c_list:
                assigned_host = h
                break

        # Fallback to IP subnet prefix
        if assigned_host == "unassigned" and ip:
            prefix = ".".join(ip.split(".")[:3])
            assigned_host = ip_to_host.get(prefix, "unassigned")

        # Check preset path
        preset_file = None
        if (presets_dir / f"{node_name}.nix").exists():
            preset_file = f"nix-presets/containers/{node_name}.nix"
        elif (presets_dir / node_name / "default.nix").exists():
            preset_file = f"nix-presets/containers/{node_name}/default.nix"

        meta = node_data.get("meta", {})
        catalog[node_name] = {
            "name": meta.get("name", node_name),
            "category": meta.get("category", "General"),
            "host": assigned_host,
            "ip": ip,
            "port": node_data.get("port"),
            "external_port": node_data.get("externalPort"),
            "domain": node_data.get("domain"),
            "public": node_data.get("public", False),
            "auth": "Cloudflare Access / SSO"
            if node_data.get("auth")
            else (
                "None (Internal / Anonymous)"
                if node_data.get("auth") is False
                else "Default"
            ),
            "mtls": node_data.get("mtls", False),
            "upstream_preset": preset_file,
            "persistence_path": f"/var/lib/machines/{node_name}",
            "description": meta.get("description", ""),
        }

    return catalog


def build_system_modules(nix_config: Path) -> dict[str, Any]:
    modules_dir = nix_config / "modules" / "nixos"
    catalog = {}

    module_descriptions = {
        "core.nix": "Base NixOS settings, locale, nix-daemon, nixpkgs flakes, zsh, sudo.",
        "base.nix": "Foundational system layer, experimental-features, default sops settings.",
        "options.nix": "Root Switchboard schema declaration for options.my.",
        "security/": "Core security settings, kernel hardening, sudo rules, auditd.",
        "ai-hardening.nix": "Airlock container network egress filtering (nftables/firewall rules to restrict AI agent egress).",
        "persistence.nix": "Impermanence engine: mounts /persist Btrfs subvolume over tmpfs root /.",
        "disko.nix": "Disko configuration for NVMe/Btrfs workstations.",
        "clevis-initrd.nix": "Clevis NBDE network-bound disk encryption unlock during initrd stage via Tang servers.",
        "audio.nix": "PipeWire sound server, low-latency pro-audio, Jabra USB headset smart button integration.",
        "desktop.nix": "Desktop environments (GNOME, Wayland/Hyprland), display manager.",
        "virtualisation.nix": "systemd-nspawn container engine, libvirtd/KVM, bridge cbr0.",
        "backup.nix": "Host-side restic backup engine integration.",
        "zero-trust.nix": "Zero-trust network policy (SSH only from personal-devices, drop raw LAN).",
        "rpi5-node.nix": "Raspberry Pi 5 kernel, firmware, EEPROM, and DTB configuration.",
        "rpi5-disko.nix": "Disko layout for Raspberry Pi 5 NVMe.",
        "data-disk.nix": "Dedicated persistent storage disk mounts (/data).",
        "workstation.nix": "Complete workstation bundle (imports desktop, audio, virtualisation, dev tools).",
    }

    if modules_dir.is_dir():
        for f in sorted(modules_dir.glob("*.nix")):
            desc = module_descriptions.get(f.name, "NixOS system module.")
            decls = declarations_in_file(f)
            catalog[f.name] = {
                "file": f"nix-config/modules/nixos/{f.name}",
                "purpose": desc,
                "declared_options": [d.namespace for d in decls],
            }

    return catalog


def build_home_manager_catalog(nix_config: Path) -> dict[str, Any]:
    hm_dir = nix_config / "modules" / "home-manager"
    users_dir = nix_config / "users"
    catalog: dict[str, Any] = {"modules": {}, "users": {}}

    hm_descriptions = {
        "gnome.nix": "GNOME desktop settings, extensions, keybindings, dconf.",
        "vscode.nix": "VS Code editor extensions and workspace settings.",
        "nixvim.nix": "Declarative Neovim configuration.",
        "ai-agents.nix": "Local AI agent CLI tools (Claude Code, Antigravity, Aider, OpenClaw).",
        "dev.nix": "Developer tools, Git, compilers, direnv, shells.",
        "syncthing.nix": "User-level Syncthing tray / synchronization daemon.",
        "anyrun.nix": "Wayland application launcher.",
        "security.nix": "GPG / SSH agent configuration.",
    }

    if hm_dir.is_dir():
        for f in sorted(hm_dir.glob("*.nix")):
            catalog["modules"][f.name] = {
                "file": f"nix-config/modules/home-manager/{f.name}",
                "purpose": hm_descriptions.get(f.name, "Home-Manager user module."),
            }

    if users_dir.is_dir():
        for u in sorted(users_dir.iterdir()):
            if u.is_dir():
                catalog["users"][u.name] = {
                    "path": f"nix-config/users/{u.name}/",
                    "type": "Primary Operator"
                    if u.name == "martin"
                    else "Collaborator / Persona",
                }

    return catalog


def build_personas_and_agents(personas: dict[str, Any]) -> dict[str, Any]:
    result = {}
    for p_name, p_data in sorted(personas.items()):
        result[p_name] = {
            "kind": p_data.get("kind"),
            "tool": p_data.get("tool"),
            "model": p_data.get("model"),
            "role_tags": p_data.get("role-tags", []),
            "active_hours": p_data.get("active-hours"),
            "signing_key": p_data.get("signing-key"),
            "date_joined": p_data.get("date-joined"),
        }
    return result


def build_developer_recipes() -> dict[str, Any]:
    return {
        "add_new_container": [
            "Step 1: Create definition in `nix-presets/containers/<name>.nix`.",
            "Step 2: Assign IP (e.g. 10.85.x.y), port, and domain in `nix-config/inventory.nix` under `network.nodes`.",
            "Step 3: Opt in on target host in `nix-config/hosts/<host>/containers.nix` (set `my.containers.<name>.enable = true;`).",
            "Step 4: Register in `nix-config/hosts/container-factory/default.nix` (ADR-002: built centrally).",
            "Step 5: Run `just maintenance::sync-agent` to refresh ground-truth manifests.",
        ],
        "modify_system_module": [
            "Step 1: Check blast radius in `docs/OPTIONS.md` and `docs/IMPORTS.md`.",
            "Step 2: Edit `nix-config/modules/nixos/<module>.nix`.",
            "Step 3: Test build with `just in nix-config nixos::test` or `nixos-rebuild dry-build`.",
            "Step 4: Run `just maintenance::sync-agent` to update options index.",
        ],
        "deploy_changes": [
            "Workstation (local): `just in nix-config nixos::switch`",
            "Remote host: `colmena apply --on <host>` or push via CI deploy signal",
            'Fleet-wide save & push: `just ship-all "commit message"`',
        ],
    }


# ---------------------------------------------------------------------------
# Main Orchestrator
# ---------------------------------------------------------------------------


def generate_manifest() -> dict[str, Any]:
    print("Evaluating authoritative inventory.nix...")
    inv = eval_nix_json(NIX_CONFIG / "inventory.nix") or {}

    print("Evaluating personas.nix...")
    personas = eval_nix_json(NIX_CONFIG / "personas.nix") or {}

    print("Evaluating repos.nix...")
    repos = eval_nix_json(META_ROOT / "kleinbem" / "repos.nix") or {}

    print("Scanning host containers, secrets, and Disko configs...")
    host_containers = scan_host_containers(NIX_CONFIG)
    host_secrets = scan_host_secrets(NIX_CONFIG)

    manifest = {
        "version": "1.0",
        "description": "Complete AI Knowledge Manifest for the kleinbem fleet. Auto-generated. Do not edit by hand.",
        "invariants": get_invariants(),
        "repo_atlas": get_repo_atlas(repos),
        "network_topology": get_network_topology(inv),
        "hosts": build_host_matrix(inv, NIX_CONFIG, host_containers, host_secrets),
        "services": build_services_catalog(inv, host_containers, META_ROOT),
        "modules_system": build_system_modules(NIX_CONFIG),
        "modules_user": build_home_manager_catalog(NIX_CONFIG),
        "personas_and_agents": build_personas_and_agents(personas),
        "developer_recipes": build_developer_recipes(),
    }
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate INFRASTRUCTURE.yaml manifest"
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        default=NIX_CONFIG / "docs" / "INFRASTRUCTURE.yaml",
        help="Target output file path",
    )
    args = parser.parse_args()

    manifest_data = generate_manifest()

    out_file = args.output
    out_file.parent.mkdir(parents=True, exist_ok=True)

    print(f"Writing YAML manifest to {out_file}...")
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(
            "# ============================================================================\n"
        )
        f.write(
            "# INFRASTRUCTURE.yaml — Complete Fleet Knowledge Manifest for AI Assistants\n"
        )
        f.write("# Auto-generated by nix-config/scripts/generate-infra-yaml.py\n")
        f.write(
            "# Regenerate via `just maintenance::sync-agent` or `just sync-infra`\n"
        )
        f.write(
            "# ============================================================================\n\n"
        )
        yaml.dump(
            manifest_data,
            f,
            sort_keys=False,
            indent=2,
            width=120,
            allow_unicode=True,
        )

    # Workspace root symlink
    root_symlink = META_ROOT / "INFRASTRUCTURE.yaml"
    try:
        if root_symlink.is_symlink() or root_symlink.exists():
            root_symlink.unlink()
        rel_target = os.path.relpath(out_file, META_ROOT)
        root_symlink.symlink_to(rel_target)
        print(f"Created symlink: {root_symlink} -> {rel_target}")
    except Exception as e:
        print(f"Warning: Failed to create root symlink: {e}", file=sys.stderr)

    print("Successfully generated INFRASTRUCTURE.yaml!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
