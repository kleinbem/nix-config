# Container hosts

The container host module lives in [nix-gantry](https://github.com/kleinbem-dev/nix-gantry): `modules/host.nix` (bridge, NAT, `services.nix-gantry.host.*`), `modules/host-persistence.nix` and `modules/updater.nix` (`services.nix-gantry.updater.*`). Its options are listed in nix-gantry's `docs/OPTIONS.md`.

Containers are systemd-nspawn, built centrally by `hosts/container-factory` and pulled by each host's updater from the release manifest.

| Host | Imports |
|---|---|
| core-pi, hass-pi, mac-mini, nasbook | `host`, `host-persistence`, `updater`; set `services.nix-gantry.host` |
| nixos-nvme, orin-nano | `updater` only, set `services.nix-gantry.updater` |

For a new host, copy the `services.nix-gantry.host` block from a similar host (core-pi is a good template), pick a free subnet in `inventory.nix`, and set `enablePersistence = true` (the fleet always uses impermanence).
