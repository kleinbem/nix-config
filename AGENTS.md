# nix-config

Primary consumer flake. Owns hosts, users, system modules, the inventory, and ground-truth docs.

## Before editing

1. **`docs/OPTIONS.md`** — auto-generated index of every `my.*` option, its declaration site, and which hosts/users opt in. Grep this first to see blast radius.
2. **`docs/SYSTEM_REFERENCE.md`** — current nixpkgs revisions, managed hosts, active services. Auto-generated.
3. **`inventory.nix`** — master source for NixOS *and* OpenWrt infrastructure. Hosts referenced here.

Both docs regenerate via `just maintenance::sync-agent` (run from repo root).

## Layout

| Path | What lives here |
|---|---|
| `hosts/<name>/` | Per-machine config. Imports modules, opts into `my.*` options. |
| `users/<name>/` | Home-Manager config per user. `nixos.nix` is the system-level slice. |
| `modules/nixos/` | System modules (Switchboard pattern — see local AGENTS.md). |
| `modules/home-manager/` | User-level modules (same pattern). |
| `modules/flake/` | flake-parts modules. |
| `pki/`, `tests/` | Supporting material. |

## Conventions

- Every option lives under `my.*` (see `modules/nixos/options.nix` for the root schema).
- Hosts default to opt-out (`enable = false`); they must explicitly opt in.
- Group attribute sets: never repeat `my.x.y` prefixes — use `my = { x.y = …; };`.
- After changing modules, regenerate the options index: `just maintenance::sync-agent`.
