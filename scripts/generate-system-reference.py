#!/usr/bin/env python3
"""Generate SYSTEM_REFERENCE.md — ground-truth doc for AI assistants.

Pulls data from:
  - nix-config/inventory.nix (hosts + network.nodes)
  - meta-workspace flake.lock (closure pins)
  - nix-config/hosts/<host>/*.nix (which containers each host enables)
  - nix-presets/containers/*.nix (source pointers for service definitions)
  - .agent/decisions/*.md (open ADRs)
  - /etc/specialisation (active spec on this machine)
  - gh CLI (recent CI run status per workflow; optional)

Designed to degrade gracefully — any subsystem can be missing and rendering
continues. The output is content-deterministic (no embedded timestamp) so a
no-op apply produces a zero-line diff.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Data extraction
# ---------------------------------------------------------------------------


def run_cmd(args: list[str], cwd: Path | None = None) -> str | None:
    try:
        result = subprocess.run(
            args,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        return result.stdout.strip()
    except (
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
        FileNotFoundError,
    ):
        return None


def load_inventory(nix_config: Path) -> dict[str, Any]:
    """Read inventory.nix's hosts + network.nodes as JSON."""
    out: dict[str, Any] = {"hosts": {}, "services": {}}
    h = run_cmd(
        ["nix", "eval", "--json", "--file", str(nix_config / "inventory.nix"), "hosts"]
    )
    s = run_cmd(
        [
            "nix",
            "eval",
            "--json",
            "--file",
            str(nix_config / "inventory.nix"),
            "network.nodes",
        ]
    )
    if h:
        out["hosts"] = json.loads(h)
    if s:
        out["services"] = json.loads(s)
    return out


def load_closure_pins(meta: Path) -> dict[str, str]:
    """Read the meta-workspace flake.lock and extract the most-important pins."""
    lockfile = meta / "flake.lock"
    if not lockfile.exists():
        return {}
    try:
        data = json.loads(lockfile.read_text())
    except json.JSONDecodeError:
        return {}
    nodes = data.get("nodes", {})
    pins: dict[str, str] = {}
    for name in (
        "nixpkgs",
        "home-manager",
        "sops-nix",
        "devenv",
        "nix-config",
        "nix-packages",
        "nix-hardware",
        "nix-presets",
        "nix-devshells",
    ):
        n = nodes.get(name, {})
        rev = n.get("locked", {}).get("rev")
        if rev:
            pins[name] = rev[:8]
    return pins


def host_container_map(nix_config: Path) -> dict[str, dict[str, bool]]:
    """Grep-heuristic: which containers are enabled on which host.

    Walks nix-config/hosts/<host>/*.nix looking for lines like:
        n8n.enable = true;
        n8n = { enable = true; ... };
        n8n.enable = lib.mkForce true;
    inside (or near) a `my.containers = {...}` or `containers = {...}` block.

    Returns {host: {container: enabled_bool}}.
    """
    result: dict[str, dict[str, bool]] = {}
    hosts_dir = nix_config / "hosts"
    if not hosts_dir.is_dir():
        return result
    for host_dir in sorted(hosts_dir.iterdir()):
        if not host_dir.is_dir():
            continue
        host_state: dict[str, bool] = {}
        for nix_file in host_dir.rglob("*.nix"):
            try:
                lines = nix_file.read_text().splitlines()
            except OSError:
                continue
            in_containers = False
            depth = 0
            current_container = None
            for raw in lines:
                line = raw.strip()
                # Track when we enter a my.containers or containers block
                if re.search(r"\b(my\.containers|containers)\s*=\s*\{", line):
                    in_containers = True
                    depth = line.count("{") - line.count("}")
                    continue
                if in_containers:
                    depth += line.count("{") - line.count("}")
                    if depth <= 0:
                        in_containers = False
                        current_container = None
                        continue
                    # name = { ... } sub-block
                    m = re.match(r"([a-z][a-z0-9-]*)\s*=\s*\{", line)
                    if m:
                        current_container = m.group(1)
                        continue
                    # name.enable = true|false
                    m = re.match(
                        r"([a-z][a-z0-9-]*)\.enable\s*=\s*(lib\.mkForce\s+)?(true|false)",
                        line,
                    )
                    if m:
                        host_state[m.group(1)] = m.group(3) == "true"
                        continue
                    # enable = true|false inside a sub-block
                    m = re.match(r"enable\s*=\s*(lib\.mkForce\s+)?(true|false)", line)
                    if m and current_container:
                        host_state[current_container] = m.group(2) == "true"
        if host_state:
            result[host_dir.name] = host_state
    return result


def container_source_map(meta: Path) -> dict[str, str]:
    """Find each container's declaration source: nix-presets/containers/<name>.nix:<line>.

    Looks for `options.my.containers.<name>` or top-level naming convention.
    """
    result: dict[str, str] = {}
    containers_dir = meta / "nix-presets" / "containers"
    if not containers_dir.is_dir():
        return result
    pat = re.compile(r"options\.my\.containers\.([a-z][a-z0-9-]*)")
    for nix_file in sorted(containers_dir.rglob("*.nix")):
        try:
            for i, line in enumerate(nix_file.read_text().splitlines(), 1):
                m = pat.search(line)
                if m:
                    name = m.group(1)
                    rel = nix_file.relative_to(meta)
                    result[name] = f"{rel}:{i}"
                    break
        except OSError:
            continue
        # Fallback: convention is <name>.nix declares container <name>
        if nix_file.stem not in result and nix_file.parent == containers_dir:
            rel = nix_file.relative_to(meta)
            result.setdefault(nix_file.stem, f"{rel}:1")
    return result


def active_specialisation() -> str | None:
    """Return the active NixOS specialisation if detectable, else None."""
    # systemd-credential approach: /run/current-system/extra-dependencies may
    # contain spec name; simpler: /etc/specialisation file (NixOS sets it).
    for p in ("/etc/specialisation", "/run/current-system/extra-dependencies"):
        if Path(p).is_file():
            txt = Path(p).read_text().strip()
            if txt:
                return txt
    return None


def ci_status(meta: Path) -> dict[str, dict[str, str]]:
    """For each meta workflow, get latest run conclusion + SHA + workflow name.

    Returns {workflow_filename: {conclusion, sha, name}}.
    Best effort; returns {} if gh missing or auth fails.
    """
    if run_cmd(["gh", "--version"]) is None:
        return {}
    wf_dir = meta / ".github" / "workflows"
    if not wf_dir.is_dir():
        return {}
    result: dict[str, dict[str, str]] = {}
    for wf in sorted(wf_dir.glob("*.yaml")):
        if wf.name.startswith("_"):
            continue
        raw = run_cmd(
            [
                "gh",
                "run",
                "list",
                "--repo",
                "kleinbem/nix",
                "--workflow",
                wf.name,
                "--branch",
                "main",
                "--limit",
                "1",
                "--json",
                "conclusion,status,headSha,displayTitle",
            ]
        )
        if not raw:
            continue
        try:
            runs = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if not runs:
            continue
        r = runs[0]
        result[wf.stem] = {
            "conclusion": r.get("conclusion", "?") or r.get("status", "?"),
            "sha": (r.get("headSha") or "")[:8],
            "title": r.get("displayTitle", ""),
        }
    return result


def open_adrs(meta: Path) -> list[dict[str, str]]:
    """List open architecture decisions from .agent/decisions/*.md."""
    adr_dir = meta / ".agent" / "decisions"
    if not adr_dir.is_dir():
        return []
    out: list[dict[str, str]] = []
    for md in sorted(adr_dir.glob("*.md")):
        if md.name in ("README.md", "000-template.md"):
            continue
        try:
            text = md.read_text()
        except OSError:
            continue
        # Heading: first # H1
        title_m = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
        title = title_m.group(1).strip() if title_m else md.stem
        # Status: prefer YAML-frontmatter `status: open`, else look for line
        status_m = re.search(r"^status:\s*(\w+)", text, re.MULTILINE | re.IGNORECASE)
        status = status_m.group(1).lower() if status_m else "unknown"
        out.append(
            {
                "file": str(md.relative_to(meta)),
                "title": title,
                "status": status,
            }
        )
    return out


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


def render(
    out: list[str],
    pins: dict[str, str],
    inventory: dict[str, Any],
    host_map: dict[str, dict[str, bool]],
    src_map: dict[str, str],
    spec: str | None,
    ci: dict[str, dict[str, str]],
    adrs: list[dict[str, str]],
    meta: Path,
) -> None:
    out.append("# 🏗️ System Reference (Auto-generated)")
    out.append("")
    # Content-deterministic pin line (no timestamp).
    pin_parts = []
    for n in ("nixpkgs", "home-manager", "sops-nix"):
        if n in pins:
            pin_parts.append(f"{n} `{pins[n]}`")
    if pin_parts:
        out.append(f"*Pin: {' · '.join(pin_parts)}*")
    out.append("")
    if spec:
        out.append(f"*Active specialisation on this machine: **{spec}***")
        out.append("")
    out.append("> [!IMPORTANT]")
    out.append(
        '> This file contains the "ground truth" for the current NixOS infrastructure.'
    )
    out.append(
        "> AI assistants MUST read this file at the start of any configuration task."
    )
    out.append("")

    # --- Core Revisions ---
    out.append("## 📦 Core Revisions")
    out.append("")
    for name, rev in pins.items():
        url = ""
        if name == "nixpkgs":
            url = f"[`{rev}`](https://github.com/NixOS/nixpkgs/commit/{rev})"
        else:
            url = f"`{rev}`"
        out.append(f"- **{name}**: {url}")
    out.append("")

    # --- Managed Hosts (with CI status overlay) ---
    out.append("## 🖥️ Managed Hosts")
    out.append("")
    sys_ci = ci.get("build-system", {})
    for name in sorted(inventory.get("hosts", {})):
        h = inventory["hosts"][name]
        ip = h.get("ip", "no-ip")
        system = h.get("system", "")
        deploy = h.get("deployType") or h.get("type") or ""
        tags = h.get("tags", []) or []
        details = ", ".join(filter(None, [system, deploy]))
        tagstr = f" — {', '.join(tags)}" if tags else ""
        line = f"- **{name}** (`{ip}`{', ' + details if details else ''}){tagstr}"
        # CI overlay: same conclusion applies to whole matrix; we mark per-host
        # only if the build-system workflow knows about this host (best effort).
        if sys_ci.get("conclusion"):
            emoji = {
                "success": "✅",
                "failure": "❌",
                "cancelled": "⏹",
                "skipped": "⏭",
                "in_progress": "🔄",
            }.get(sys_ci["conclusion"], "❔")
            line += f"  · CI: {emoji}"
        out.append(line)
    out.append("")

    # --- Services grouped by host ---
    out.append("## 📡 Network Services (by host)")
    out.append("")
    services = inventory.get("services", {})
    # Build reverse: service -> set of hosts that enable it
    enabled_on: dict[str, list[str]] = {}
    for host, container_state in host_map.items():
        for cname, enabled in container_state.items():
            if enabled:
                enabled_on.setdefault(cname, []).append(host)

    # Filter out false positives — only render names that are ACTUAL containers
    # (i.e., declared in nix-presets/containers/). The host-config heuristic
    # picks up nested option blocks like `tls`, `manager`, `agents` which
    # aren't containers themselves; src_map is the canonical container set.
    canonical = set(src_map.keys())

    # Render each host's enabled containers
    for host in sorted(host_map):
        enabled_here = sorted(
            c for c, e in host_map[host].items() if e and c in canonical
        )
        if not enabled_here:
            continue
        out.append(f"### {host}")
        out.append("")
        for cname in enabled_here:
            svc = services.get(cname, {})
            meta_d = svc.get("meta", {})
            icon = meta_d.get("icon", "📦")
            display = meta_d.get("name", cname)
            ip = svc.get("ip", "")
            port = svc.get("port")
            domain = svc.get("domain")
            desc = meta_d.get("description", "")
            src = src_map.get(cname)
            addr = ip
            if port:
                addr = f"{ip}:{port}" if ip else f":{port}"
            line_parts = [f"- {icon} **{display}** (`{cname}`)"]
            if addr:
                line_parts.append(f"`{addr}`")
            if domain:
                line_parts.append(f"→ `{domain}`")
            if desc:
                line_parts.append(f"— {desc}")
            if src:
                line_parts.append(f"_[src: {src}]_")
            out.append(" ".join(line_parts))
        out.append("")

    # --- Declared but not enabled anywhere ---
    all_declared = set(src_map.keys()) | set(services.keys())
    used = set(enabled_on.keys())
    unused = sorted(all_declared - used)
    if unused:
        out.append("### Declared but not currently enabled on any host")
        out.append("")
        for cname in unused:
            svc = services.get(cname, {})
            meta_d = svc.get("meta", {})
            display = meta_d.get("name", cname)
            src = src_map.get(cname)
            line = f"- `{cname}`" + (f" — {display}" if display != cname else "")
            if src:
                line += f" _[src: {src}]_"
            out.append(line)
        out.append("")

    # --- Workspace Status (from system level) ---
    out.append("## 🛠️ Workspace Status")
    out.append("")
    if run_cmd(["devenv", "--version"]) is not None:
        out.append("- **Devenv**: Available")
    else:
        out.append("- **Devenv**: Not found in path")
    guard = run_cmd(["systemctl", "--user", "is-active", "workspace-guardian.service"])
    if guard == "active":
        out.append("- **Autonomous Guardian**: Active ✅")
    else:
        out.append("- **Autonomous Guardian**: Inactive ❌")
    out.append("")

    # --- CI Status (overall, per workflow) ---
    if ci:
        out.append("## 🚦 CI Status (latest run per workflow on `main`)")
        out.append("")
        emoji_map = {
            "success": "✅",
            "failure": "❌",
            "cancelled": "⏹",
            "skipped": "⏭",
            "in_progress": "🔄",
        }
        for wf_name in sorted(ci):
            info = ci[wf_name]
            e = emoji_map.get(info["conclusion"], "❔")
            out.append(f"- {e} **{wf_name}** — `{info['sha']}` — {info['title']}")
        out.append("")

    # --- Open ADRs ---
    open_adrs_list = [a for a in adrs if a["status"] in ("open", "proposed", "unknown")]
    if open_adrs_list:
        out.append("## 📜 Open Decisions (ADRs)")
        out.append("")
        for adr in open_adrs_list:
            out.append(
                f"- **{adr['title']}** (`{adr['status']}`) — _[src: {adr['file']}]_"
            )
        out.append("")

    # --- AI Capabilities (MCP Tools) ---
    out.append("## 🤖 AI Capabilities (MCP Tools)")
    out.append("")
    mcp = meta / "scripts" / "workspace-mcp.py"
    if mcp.is_file():
        out.extend(render_mcp_tools(mcp))
    out.append("")


def render_mcp_tools(mcp: Path) -> list[str]:
    """Parse @mcp.tool() functions, return one bullet per tool."""
    import ast

    try:
        tree = ast.parse(mcp.read_text())
    except (OSError, SyntaxError):
        return ["- _(MCP parse failed)_"]
    out: list[str] = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        is_tool = any(
            (
                isinstance(d, ast.Call)
                and isinstance(d.func, ast.Attribute)
                and d.func.attr == "tool"
            )
            or (isinstance(d, ast.Attribute) and d.attr == "tool")
            for d in node.decorator_list
        )
        if not is_tool:
            continue
        doc = (ast.get_docstring(node) or "").strip().split("\n")[0].strip().rstrip(".")
        if doc:
            out.append(f"- **{node.name}** — {doc}.")
        else:
            out.append(f"- **{node.name}** — _(no docstring)_")
    return out


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--nix-config", required=True, type=Path)
    parser.add_argument("--meta", required=True, type=Path)
    parser.add_argument("--no-ci", action="store_true", help="Skip CI status (faster)")
    args = parser.parse_args()

    nix_config: Path = args.nix_config
    meta: Path = args.meta

    print("  🔍 Loading inventory…", flush=True)
    inv = load_inventory(nix_config)
    print("  📌 Resolving closure pins…", flush=True)
    pins = load_closure_pins(meta)
    print("  🗺️  Mapping containers to hosts…", flush=True)
    host_map = host_container_map(nix_config)
    print("  🔗 Locating service source files…", flush=True)
    src_map = container_source_map(meta)
    spec = active_specialisation()
    if not args.no_ci:
        print("  🚦 Querying CI status…", flush=True)
        ci = ci_status(meta)
    else:
        ci = {}
    print("  📜 Reading ADRs…", flush=True)
    adrs = open_adrs(meta)

    print("  ✍️  Rendering…", flush=True)
    out_lines: list[str] = []
    render(out_lines, pins, inv, host_map, src_map, spec, ci, adrs, meta)
    output = "\n".join(out_lines).rstrip() + "\n"
    target = nix_config / "docs" / "SYSTEM_REFERENCE.md"
    target.write_text(output)
    print(f"  ✅ Wrote {target.relative_to(meta)}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
