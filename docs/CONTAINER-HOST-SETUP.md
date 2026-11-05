# Container hosts

The container host module lives in [nix-gantry](https://github.com/kleinbem-dev/nix-gantry): `modules/host.nix` (bridge, NAT, `my.container-host.*`), `modules/host-persistence.nix` and `modules/updater.nix`. Its options are listed in nix-gantry's `docs/OPTIONS.md`.

Containers are systemd-nspawn, built centrally by `hosts/container-factory` and pulled by each host's updater from the release manifest.

| Host | Imports |
|---|---|
| core-pi, hass-pi, mac-mini, nasbook | `host`, `host-persistence`, `updater`; set `my.container-host` |
| nixos-nvme, orin-nano | `updater` only, no `my.container-host` |

For a new host, copy the `container-host` block from a similar host (core-pi is a good template), pick a free subnet in `inventory.nix`, and set `enablePersistence = true` (the fleet always uses impermanence).
