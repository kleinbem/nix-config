# nix-config

![CI](https://github.com/kleinbem/nix-config/actions/workflows/ci.yml/badge.svg)

NixOS configuration for the kleinbem fleet: hosts, users, system modules and the inventory. Service presets, hardware, packages and devshells come from the sibling `nix-*` repos; secrets from kleinbem-secrets.

## Hosts

| Host | Role |
|---|---|
| nixos-nvme | GNOME workstation |
| mac-mini | Always-on services (monitoring, mail, Forgejo, AI) |
| core-pi | Edge hub: Caddy, Attic, Authentik, Vaultwarden |
| hass-pi | Home Assistant |
| nasbook | NAS, documents, backups |
| orin-nano | Jetson edge AI and cameras |
| phone, tablet | nix-on-droid |
| container-factory | Builds the standalone container images |

`inventory.nix` is the source of truth for hosts and addresses; `docs/INFRASTRUCTURE.yaml` has the generated full picture.

## Layout

```text
hosts/<name>/            per-machine config
users/<name>/            Home Manager (home.nix) and account (nixos.nix)
modules/nixos/           system modules, all under my.* (security/ has ClamAV, USBGuard, sudo, ssh)
modules/home-manager/    user modules
modules/flake/           flake-parts: hosts, checks, colmena, images
inventory.nix            hosts, networks, container addresses
docs/                    guides and generated references
```

## Commands

`just` lists everything. The common ones:

```bash
just apply              # pull, verify, switch this machine (dev::apply)
just switch             # switch from the local tree
just dev::preflight     # formatting, pre-commit-check, host eval: run before pushing
just dev::check-hosts   # nix flake check over all hosts
just dev::impact <file> # which hosts a change to that file touches
just dev::sync-agent    # regenerate the docs in docs/
just nixos::test-vm     # boot nixos-nvme in a VM
just deployment::deploy <host>   # emergency deploy over SSH
```

Hosts normally deploy themselves from the `production` branch; see [docs/DEPLOYMENT-STRATEGY.md](docs/DEPLOYMENT-STRATEGY.md). All docs: [docs/README.md](docs/README.md).
