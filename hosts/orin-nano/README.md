# Orin Nano Plus: NixOS installation

> **Warning: every install recipe below except `orin-update-usb` wipes the target SSD.** Check the
> device argument with `lsblk` first. The recipes ask for confirmation, but
> they do not know which disk you meant.

> **Back up the Frigate SSD key first.** The second SSD's LUKS keyfile,
> `/nix/persist/etc/crypt/frigate.key`, lives only on the main SSD (it is not
> in sops). Wiping the main SSD without a copy leaves the Frigate recordings
> unreadable. Copy it off the Orin before any reinstall of the main SSD:
>
> ```bash
> (umask 077; ssh orin-nano sudo cat /nix/persist/etc/crypt/frigate.key > frigate.key.new \
>   && [ -s frigate.key.new ] && mv frigate.key.new frigate.key || rm -f frigate.key.new)
> ```
>
> Keep the copy somewhere encrypted (e.g. a Bitwarden attachment), not as a
> plain file. Path A keeps the Frigate SSD: put the key back on the Orin after
> the first boot, then reboot:
>
> ```bash
> ssh orin-nano 'sudo install -D -m 0400 /dev/stdin /nix/persist/etc/crypt/frigate.key' < frigate.key
> ```
>
> Path B reformats it and needs a key during install (see below). Delete the
> local copy afterwards (`shred -u frigate.key`).

## Install

Two ways, both run from the nix-config repo root on the workstation. Recipes
live in [`.just/deployment.just`](../../.just/deployment.just).

### A. SSD in a USB reader (preferred)

Put the Orin's SSD in a USB-NVMe enclosure on the workstation:

```bash
lsblk                                   # find the SSD, e.g. /dev/sdb
just deployment::orin-install-usb /dev/sdb
```

The device is a positional argument (`device=/dev/sdb` after the recipe name
would be passed literally). This wipes that SSD only (it runs disko with
`secondDiskDevice = null`, so the Frigate SSD is untouched), partitions it with
[`disko.nix`](./disko.nix), builds the closure, installs systemd-boot to the
ESP, adds the new host age key to sops and binds LUKS to Tang. Then:

1. Commit and push the re-encrypted secrets in kleinbem-secrets, then bump
   the `kleinbem-secrets` input in nix-config (`nix flake update
   kleinbem-secrets`) and commit `flake.lock`: `deploy-orin` builds from the
   pinned revision.
2. Put the SSD back in the Orin, connect ethernet and boot.
3. Run `just deployment::deploy-orin` once. The installed closure predates the
   sops re-encryption, so runtime secrets (NetBird setup key included) don't
   decrypt until this first deploy.

`just deployment::orin-update-usb /dev/sdb` reinstalls onto an already
provisioned SSD without wiping it.

### B. Bootstrap image, then promote over SSH

```bash
just deployment::orin-install-bootstrap /dev/sdb   # wipes /dev/sdb
# boot the Orin from that SSD; root SSH by key only
just deployment::orin-promote root@orin-nano-bootstrap.local frigate.key   # wipes BOTH Orin SSDs
```

`orin-promote` runs nixos-anywhere against `root@orin-nano-bootstrap.local` and
builds natively on the Orin. Its disko phase uses the full orin-nano config,
which also declares the second SSD (`/dev/nvme1n1`), so it **reformats the
Frigate SSD too**: back up `/mnt/data/frigate` first if the recordings matter.
disko formats it with `/nix/persist/etc/crypt/frigate.key`, which doesn't
exist in the installer, so pass a keyfile as the second argument (the backup,
or `(umask 077; head -c 64 /dev/urandom > frigate.key)` for a new one); it is
copied in with nixos-anywhere's `--disk-encryption-keys`. After the first boot,
install the same file at that path as in path A.

`orin-promote-nokexec` skips the RAM boot, so it needs a target disk that
isn't in use. The bootstrap system runs from the very SSD it would format, so
it is not a fallback for this path; use path A instead.

## After the first boot

- **NetBird** joins on its own (`netbird-autojoin`, setup key from sops) once
  the first `deploy-orin` has run. Check with `sudo netbird status`.
- **FIDO2 unlock** is not enrolled by the installer (it only binds Tang).
  Enrol both YubiKeys once, on the Orin:
  `sudo systemd-cryptenroll --fido2-device=auto /dev/disk/by-partlabel/disk-main-luks`
  (run it twice, once per key).
- **Later updates** arrive through comin pull-deploy. The Orin still builds
  its kernel/L4T closure on the device, so there is no cache requirement and
  the build timeout is 12 h.

## Disk layout

Defined in [`disko.nix`](./disko.nix). `/` and `/var` are tmpfs
(impermanence); state that must survive a reboot lives under `/nix/persist`.

```
Main SSD (GPT)
├── ESP   (1G, vfat)              → /boot (systemd-boot)
├── swap  (16G, random key)
└── LUKS  (rest)                  → orin_crypt
    └── LVM vg_orin
        ├── nix    (128G, ext4)   → /nix
        ├── models (256G, ext4)   → /mnt/models
        └── data   (rest, btrfs)  → /mnt/data

Second SSD (GPT)
└── LUKS (keyfile on /nix/persist) → orin_frigate_crypt
    └── ext4                       → /mnt/data/frigate (Frigate recordings)
```

The second disk is unlocked in stage 2 by crypttab (see `services.nix`): its
keyfile is inside `orin_crypt`, which initrd hasn't mounted yet.

## Security model

- **Disk unlock**: the Jetson has no TPM, so there is no TPM sealing
  (`orin-seal` is inert). Tang/clevis unlocks `orin_crypt` unattended when a
  Tang server on the LAN answers. Otherwise type the passphrase, at the
  console or over initrd SSH on port 2222, or plug an enrolled YubiKey
  (FIDO2, see above) into the Orin itself; SSH doesn't forward the token.
- **SSH**: key-only (YubiKey/FIDO2). Port 22 is open on NetBird (`wt0`) and
  also on the LAN interface (`enP8p1s0`), which keeps it reachable when
  NetBird is down.
- **Bootloader**: systemd-boot, capped at 10 entries. extlinux is off.
- **Firewall**: iptables-legacy (see `network.nix`).
