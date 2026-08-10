# Orin Nano Plus — NixOS Installation

## Prerequisites

- Orin Nano booting **any Linux with SSH** (stock JetPack Ubuntu works)
- Your workstation with this Nix config repo

## Installation

### 1. First boot with stock JetPack

Power on the Orin Nano with the SSD installed. Complete the initial JetPack Ubuntu setup, then note its IP:

```bash
# On the Orin Nano:
ip addr
```

### 2. Enable SSH & copy your key

```bash
# On the Orin Nano (if SSH isn't running):
sudo systemctl start ssh

# From your workstation:
ssh-copy-id root@<orin-ip>
```

### 3. Install NixOS 🚀

```bash
# From the workspace root:
just orin-install root@<orin-ip>
```

`nixos-anywhere` will SSH in, kexec into a temporary NixOS installer, partition the SSD natively via `disko.nix`, copy the NixOS closure, install the bootloader, and reboot into NixOS.

### 4. First boot — NetBird setup

After NixOS boots, connect via the **local network** (SSH is open on LAN for the first boot only until NetBird is set up):

```bash
ssh martin@<orin-ip>

# Authenticate NetBird:
sudo netbird up --setup-key <your-setup-key>

# Verify:
sudo netbird status
```

Once NetBird is authenticated, SSH is **locked down to NetBird only** (interface `wt0`) — no more LAN exposure. Note that this system uses a **stateless root**; however, your NetBird identity and LUKS keys are persisted in `/nix/persist`.

### 5. Seal TPM2

```bash
# From your workstation (over Tailscale now):
just orin-seal
```

### 6. Future updates

```bash
# Deploy config changes (over Tailscale):
just deploy-orin
```

## Disk Layout

Defined in [`disko.nix`](./disko.nix):

```
SSD (GPT)
├── ESP   (1G, vfat)        → /boot
└── LUKS  (remaining)       → orin_crypt
    └── LVM (vg_orin)
        ├── root (128G, ext4)   → /
        └── data (rest, btrfs)  → /mnt/data
```

## Security Model

- **SSH**: Key-only auth (YubiKey), restricted to `tailscale0` interface
- **Disk**: LUKS encryption with TPM2 auto-unlock
- **Network**: All management traffic over Tailscale (WireGuard)
- **Updates**: Deployed from workstation via `nixos-rebuild` over Tailscale SSH

## How nixos-anywhere Works

The stock JetPack Ubuntu is just a **stepping stone** — `nixos-anywhere` completely replaces it. Under the hood:

1. SSHs into the running Linux
2. Kexec boots a temporary NixOS installer in RAM
3. Runs `disko` **natively** on the device (no QEMU cross-arch issues)
4. Copies the NixOS system closure
5. Installs the extlinux bootloader
6. Reboots into NixOS
