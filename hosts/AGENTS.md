# hosts/ — per-machine configurations

One subdirectory per machine. Each host's `default.nix` is the entry point referenced by `flake.nix`.

## What a host file owns

- **Hardware**: imports from `nix-hardware` (`inputs.nix-hardware.nixosModules.<host>`).
- **Module imports**: `modules/nixos/default.nix` (the common bundle) plus any presets from `nix-presets`.
- **Opt-ins**: `my.*.enable = true` for the modules / containers / services this host runs.
- **Host-specific**: hostname, IP, filesystem layout, user accounts to enable.

Everything else should live in a module, preset, or the inventory — not inline in the host.

## Adding a new host — checklist

1. Add the host to `../inventory.nix` (single source of truth).
2. Create `<name>/default.nix` with the import skeleton (copy from a similar host).
3. Wire hardware: add a module under `../../nix-hardware/` if the device isn't already supported.
4. Add the host to `flake.nix` under `nixosConfigurations` (in `nix-config/flake.nix`).
5. Pick presets / modules to opt in. Grep `../docs/OPTIONS.md` for available `my.*` options.
6. Add SSH keys via `keys.nix` if the host needs to be deployable.
7. Run `just maintenance::sync-agent` and `just maintenance::check-hosts`.

## Existing hosts

The set is dynamic — check `ls ../hosts/` or the auto-generated host list in `../docs/SYSTEM_REFERENCE.md`. For a per-host breakdown of which modules / presets / hardware / users a given host imports, see `../docs/IMPORTS.md`.

## Don't

- Don't declare `my.*` options here — only set them. Declarations belong in `../modules/` or `nix-presets/`.
- Don't inline service configuration that should live in a reusable module.
