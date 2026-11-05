# Orin Nano Plus: NixOS installation

> **Warning: every install recipe below except `orin-update-usb` wipes the target SSD.** Check the
> `device=` argument with `lsblk` first. The recipes ask for confirmation, but
> they do not know which disk you meant.

## Install

Two ways, both run from the nix-config repo root on the workstation. Recipes
live in [`.just/deployment.just`](../../.just/deployment.just).

### A. SSD in a USB reader (preferred)

Put the Orin's SSD in a USB-NVMe enclosure on the workstation:

```bash
lsblk                                         # find the SSD, e.g. /dev/sdb
just deployment::orin-install-usb device=/dev/sdb
```

This wipes the SSD, partitions it with [`disko.nix`](./disko.nix), builds the
closure, installs systemd-boot to the ESP, adds the new host age key to sops
and binds LUKS to Tang. Then commit the re-encrypted secrets, put the SSD back
in the Orin, connect ethernet and boot. The recipe prints the remaining
first-boot steps.

`just deployment::orin-update-usb` reinstalls onto an already provisioned SSD
without wiping it.

### B. Bootstrap image, then promote over SSH

```bash
just deployment::orin-install-bootstrap device=/dev/sdb   # wipes /dev/sdb
# boot the Orin from that SSD; root SSH by key only
just deployment::orin-promote                             # wipes the Orin's SSD again
```

`orin-promote` runs nixos-anywhere against `root@orin-nano-bootstrap.local` and
builds natively on the Orin. If kexec fails on the Jetson, use
`orin-promote-nokexec`.

## After the first boot

- **NetBird** joins on its own (`netbird-autojoin`, setup key from sops).
  Check with `sudo netbird status`.
- **Updates** arrive through comin pull-deploy. The Orin still builds its
  kernel/L4T closure on the device, so there is no cache requirement and the
  build timeout is 12 h. There is no manual push step.

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
  Tang server on the LAN answers; otherwise use the YubiKey (FIDO2) or the
  passphrase, either at the console or over initrd SSH on port 2222.
- **SSH**: key-only (YubiKey/FIDO2). Port 22 is open on NetBird (`wt0`) and
  also on the LAN interface (`enP8p1s0`), which keeps it reachable when
  NetBird is down.
- **Bootloader**: systemd-boot, capped at 10 entries. extlinux is off.
- **Firewall**: iptables-legacy (see `network.nix`).
