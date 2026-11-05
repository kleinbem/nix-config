# Backup and recovery

Every NixOS host runs the backup engine from nix-presets (`nixosModules/backup-engine`), wired up in `modules/nixos/backup.nix` and turned on with `my.backup.enable = true`. All six hosts have it on.

## What gets backed up

Modules and presets register their own data under `my.backup.items.<name>`; hosts add extra items (see nasbook). Each item has a tier:

- **secure**: small, critical data. Every run builds one tarball, encrypts it with age to both YubiKeys (`keys.age.yubikey-primary`, `keys.age.yubikey-backup`), and uploads `<host>-<timestamp>.tar.gz.age` to `<remote>/secure/<host>/`. Daily at 02:30. If an item's dump fails or a path is missing, the rest still uploads as `<host>-<timestamp>-partial.tar.gz.age` and the job fails; a full restore takes the newest bundle without `-partial`.
- **bulk**: large data, one restic repo per destination at `<remote>/restic/<host>`. Daily at 03:15.

Items can also list `sqlite` files (copied with `.backup`), `postgres` clusters (`pg_dumpall`) or a `command` whose output is stored. Databases are dumped, never copied live.

Not backed up, because they rebuild from source: `/nix/store`, container images (container-factory), and everything on the tmpfs root that isn't persisted.

## Where it goes

| Destination | Remote | Notes |
|---|---|---|
| r2 | `r2:kleinbem-backup` | Required. `secure/` has a 30-day bucket lock, so a compromised host can't erase its recent history. Per-host credentials in `backup_r2_rclone_config` (`nix/per-host/<host>.yaml`). |
| gdrive | `gdrive-fleet:kleinbem-backups` | Best effort. Secure bundles pruned after 365 days. |

Secrets in kleinbem-secrets: `backup_r2_rclone_config` per host; `rclone_config`, `restic_password`, `ntfy_alert_topic` (and optional `ntfy_alert_token`) in `nix/shared.yaml`.

## Monitoring

Failed jobs and stale backups (`backup-freshness-check`, daily 08:00) send an ntfy alert to the alert topic. Check a host by hand:

```bash
systemctl list-timers 'backup-*' 'restic-backups-*'
systemctl status backup-secure restic-backups-bulk-r2
journalctl -u backup-secure -n 50
```

Run a backup now: `sudo systemctl start backup-secure` or `sudo systemctl start restic-backups-bulk-r2`.

## Restore

**Secure bundle** (needs one of the two YubiKeys):

```bash
rclone --config <rclone config> lsf r2:kleinbem-backup/secure/<host>/
rclone --config <rclone config> copy r2:kleinbem-backup/secure/<host>/<file>.tar.gz.age .
age-plugin-yubikey --identity > yubikey-identity.txt   # identity stub, not the key
age -d -i yubikey-identity.txt <file>.tar.gz.age | tar -xz -C <restore-dir>
```

The tarball holds `dumps/` (database dumps) plus the item paths relative to `/`. Stop the service before copying its data back.

**Bulk** (on the host, as root; the NixOS restic module installs a `restic-bulk-<dest>` wrapper with repo and password set):

```bash
sudo restic-bulk-r2 snapshots
sudo restic-bulk-r2 restore latest --target <restore-dir> --include <path>
```

## Rebuilding a host

1. Install from the flake with the host's install recipe. They wipe the target disk:

   ```bash
   just deployment::pi-install-usb <host> [device]     # core-pi, hass-pi; device defaults to /dev/sdc
   just deployment::nasbook-install-usb <device>
   just deployment::mac-mini-install-usb <device>
   just deployment::orin-install-usb [device]          # defaults to /dev/sdb
   ```

2. If the host got a new SSH host key, its age key changed: update its anchor in `kleinbem-secrets/.sops.yaml`, run `sops updatekeys` on every file that recipient matches (`nix/per-host/<host>.yaml`, `nix/shared.yaml`, any `nix/per-container/*.yaml` it uses), and check the recipients in the file metadata.
3. Restore the data from the secure bundle or restic, then deploy.

## Keys

The fleet's master age keys are the two YubiKeys; there is no software master key to copy. Keep the backup YubiKey somewhere other than the primary. Never write a decrypted key or secret to disk; to remove a recipient (lost YubiKey, retired host), delete it from `.sops.yaml` and run `sops updatekeys` over every file it matched.

Git history lives on GitHub; the config repos rebuild every host from there.

## Router

core-gateway is a BPI-R4 running OpenWrt, not NixOS. Its config comes from openwrt-config (Ansible) and its image from openwrt-builder; see their docs for recovery.
