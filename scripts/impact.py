#!/usr/bin/env python3
"""Blast-radius lookup for changed files.

Usage:
  scripts/impact.py path/to/file.nix [more files…]
  scripts/impact.py --git              # changed files (jj since main, else git status)

For each path, prints which hosts / users / presets are downstream consumers.

Designed to be run before committing — catches the common AI failure mode of
editing a module without realizing two other hosts also consume it.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _nix_options import (
    CONSUMER_DIRS,
    NIX_CONFIG,
    REPO,
    _normalize_rel,
    consumer_label,
    consumer_paths_in_file,
    declarations_in_file,
    iter_nix_files,
    relpath,
)

# Repos whose changes this script can classify; nix-config is this checkout
# (a jj workspace when run from one), the rest are siblings in the fleet root.
SCAN_REPOS = [NIX_CONFIG] + [
    REPO / n
    for n in (
        "nix-presets",
        "nix-hardware",
        "nix-packages",
        "nix-devshells",
        "nix-templates",
    )
]


def _changed_in_repo(r: Path) -> list[str] | None:
    """Changed paths relative to r, or None if r isn't a jj/git repo.
    jj first: workspaces have no .git, and jj shows everything since main."""
    if (r / ".jj").is_dir():
        try:
            out = subprocess.check_output(
                [
                    "jj",
                    "diff",
                    "--name-only",
                    "--from",
                    "fork_point(trunk() | @)",
                    "--to",
                    "@",
                ],
                cwd=r,
                text=True,
                stderr=subprocess.DEVNULL,
            )
            return out.splitlines()
        except (subprocess.CalledProcessError, FileNotFoundError):
            pass
    if (r / ".git").exists():
        try:
            out = subprocess.check_output(
                ["git", "status", "--porcelain", "-z", "-uall"], cwd=r, text=True
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            return None
        files: list[str] = []
        entries = out.split("\0")
        i = 0
        while i < len(entries):
            e = entries[i]
            i += 1
            if len(e) < 4:
                continue
            files.append(e[3:])
            if e[0] in "RC":  # -z puts the rename source in the next entry
                i += 1
        return files
    return None


def git_changed_files() -> list[Path]:
    """Changed .nix files in nix-config and the sibling nix repos."""
    paths: list[Path] = []
    for r in SCAN_REPOS:
        names = _changed_in_repo(r)
        if names is None:
            if r == NIX_CONFIG:
                print(f"⚠️  {r}: neither a jj nor a git repo", file=sys.stderr)
            continue
        for name in names:
            p = (r / name).resolve()
            if p.suffix == ".nix" and p.exists():
                paths.append(p)
    return paths


def classify(path: Path) -> str:
    """Return a short tag describing what kind of file this is."""
    rel = _normalize_rel(path.resolve())
    if rel.is_absolute():
        return "external"
    parts = rel.parts
    if parts[:2] == ("nix-config", "hosts"):
        return "host"
    if parts[:2] == ("nix-config", "users"):
        return "user"
    if parts[:2] == ("nix-config", "modules"):
        return "module"
    return {
        "nix-presets": "preset",
        "nix-hardware": "hardware",
        "nix-packages": "package",
        "nix-devshells": "devshell",
        "nix-templates": "template",
    }.get(parts[0], "other")


def host_consumers_of_namespaces(namespaces: set[str]) -> dict[str, set[str]]:
    """For a set of `my.X` namespaces, return {namespace: {consumer labels}}."""
    out: dict[str, set[str]] = {ns: set() for ns in namespaces}
    for d in CONSUMER_DIRS:
        for f in iter_nix_files(d):
            paths = consumer_paths_in_file(f)
            if not paths:
                continue
            for ns in namespaces:
                for p in paths:
                    if p == ns or p.startswith(ns + "."):
                        out[ns].add(consumer_label(f))
                        break
    return out


def hosts_importing_user(user_name: str) -> list[str]:
    """Find hosts that import this user's nixos module."""
    hosts_dir = NIX_CONFIG / "hosts"
    needle = f"users/{user_name}/"
    hits = []
    for f in iter_nix_files(hosts_dir):
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if needle in text:
            hits.append(f.relative_to(hosts_dir).parts[0])
    return sorted(set(hits))


def hosts_importing_preset(preset_label: str) -> list[str]:
    """Heuristic: hosts that grep-match `nixosModules.<basename>`.

    `preset_label` is e.g. `preset:nix-presets/containers/attic.nix` —
    the module name is typically the filename stem.
    """
    # Extract filename stem
    rel = preset_label.split(":", 1)[1]
    stem = Path(rel).stem
    if stem == "default":
        stem = Path(rel).parent.name
    hosts_dir = NIX_CONFIG / "hosts"
    needle = f"nixosModules.{stem}"
    hits = []
    for f in iter_nix_files(hosts_dir):
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if needle in text:
            hits.append(f.relative_to(hosts_dir).parts[0])
    return sorted(set(hits))


def report_for_path(path: Path) -> list[str]:
    """Return human-readable lines describing the blast radius."""
    lines: list[str] = []
    kind = classify(path)
    rel = relpath(path)
    lines.append(f"📄 {rel}  ({kind})")

    if kind in ("module", "preset"):
        decls = declarations_in_file(path)
        if decls:
            namespaces = {d.namespace for d in decls}
            consumers = host_consumers_of_namespaces(namespaces)
            for d in sorted(decls, key=lambda x: x.namespace):
                ns = d.namespace
                cs = sorted(consumers.get(ns, set()))
                if cs:
                    lines.append(f"   ↳ `{ns}` → {', '.join(cs)}")
                elif d.default_enabled:
                    lines.append(
                        f"   ↳ `{ns}` → default-enabled (active wherever this module is imported)"
                    )
                else:
                    lines.append(f"   ↳ `{ns}` → (no opt-ins detected)")
        # Even files without `options.my.*` can be imported as nixosModules
        if kind == "preset":
            hosts = hosts_importing_preset(f"preset:{rel}")
            if hosts:
                lines.append(f"   ↳ imported as preset by hosts: {', '.join(hosts)}")
    elif kind == "host":
        # Host edits affect only that host
        parts = _normalize_rel(path.resolve()).parts
        if len(parts) >= 3:
            lines.append(f"   ↳ affects host: {parts[2]}")
    elif kind == "user":
        parts = _normalize_rel(path.resolve()).parts
        if len(parts) >= 3:
            user = parts[2]
            hosts = hosts_importing_user(user)
            if hosts:
                lines.append(
                    f"   ↳ user `{user}` imported by hosts: {', '.join(hosts)}"
                )
            else:
                lines.append(f"   ↳ user `{user}` not currently imported by any host")
    elif kind == "hardware":
        lines.append(
            "   ↳ check which host imports this hardware module via nix-hardware"
        )
    else:
        lines.append(
            f"   ↳ no automatic impact analysis for `{kind}` — review manually"
        )
    return lines


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0

    paths: list[Path]
    if argv[0] == "--git":
        paths = git_changed_files()
        if not paths:
            print("No changed .nix files in nix-config or the sibling nix repos.")
            return 0
    else:
        paths = []
        for a in argv:
            p = Path(a).resolve()
            if not p.exists():
                print(f"⚠️  {a}: file not found", file=sys.stderr)
                continue
            paths.append(p)

    if not paths:
        return 1

    for i, p in enumerate(paths):
        if i:
            print()
        for line in report_for_path(p):
            print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
