# nix-config docs

## Generated (never edit by hand)

`just dev::sync-agent` rewrites these; CI's sync-docs workflow regenerates them on every PR.

| File | What |
|---|---|
| [INFRASTRUCTURE.yaml](INFRASTRUCTURE.yaml) | Whole fleet in one file: hosts, storage, networks, containers, modules, personas, secrets. Read this first. |
| [SYSTEM_REFERENCE.md](SYSTEM_REFERENCE.md) | Pinned revisions, hosts, enabled services per host. |
| [OPTIONS.md](OPTIONS.md) | Every `my.*` option, where it's declared and who sets it. |
| [IMPORTS.md](IMPORTS.md) | Per-host import map and reverse index. |

## Guides

| File | What |
|---|---|
| [FLEET-ARCHITECTURE.md](FLEET-ARCHITECTURE.md) | How the repos, hosts and networks fit together |
| [DEVICE-TIERS.md](DEVICE-TIERS.md) | Device tiers, new-host checklist and template |
| [MODULE-ORGANIZATION.md](MODULE-ORGANIZATION.md) | Module import patterns and gotchas |
| [CONTAINER-HOST-SETUP.md](CONTAINER-HOST-SETUP.md) | Where the container host module lives and who uses it |
| [DEPLOYMENT-STRATEGY.md](DEPLOYMENT-STRATEGY.md) | Build, promote, comin; canary and rollback |
| [SECRETS-MANAGEMENT.md](SECRETS-MANAGEMENT.md) | sops-nix and kleinbem-secrets |
| [BACKUP-RECOVERY.md](BACKUP-RECOVERY.md) | Backup engine, restore, rebuilding a host |
| [HOME-MANAGER-SETUP.md](HOME-MANAGER-SETUP.md) | User environments |
| [HOME-ASSISTANT.md](HOME-ASSISTANT.md) | Home Assistant on hass-pi |
| [STALWART.md](STALWART.md) | Persona mail server on mac-mini |
| [QUICK-REFERENCE.md](QUICK-REFERENCE.md) | Common commands |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Diagnosing common problems |

Fleet maintenance automation lives in the kleinbem repo: [MAINTENANCE-AUTOMATION.md](https://github.com/kleinbem/kleinbem/blob/main/docs/MAINTENANCE-AUTOMATION.md).
