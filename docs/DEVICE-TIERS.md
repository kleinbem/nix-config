# Device Tiers & Configuration Patterns

This document defines the tiers for the kleinbem fleet and the configuration patterns each device should follow.

---

## Overview

Devices are organized into tiers based on **role**, **hardware**, and **network characteristics**. Each tier has a standardized configuration pattern to ensure consistency and simplify onboarding.

```
Tier              Hardware    Count   Role                        Example
─────────────────────────────────────────────────────────────────────────
Workstation       x86_64      2       Desktop, interactive access nixos-nvme, mac-mini
Edge Hub          aarch64     1       Services, containers        core-pi
Edge Node         aarch64     3+      Specialized compute         orin-nano, nasbook, hass-pi
Mobile            aarch64     1       Nix on Droid               phone
```

---

## Tier Definitions

### 🖥️ Workstation Tier

**Purpose:** Interactive desktop environments, development, container hosting for user-facing services.

**Characteristics:**
- x86_64-linux or equivalent
- 16+ GB RAM
- SSD storage (NVMe or SATA)
- Display/RDP access (GUI expected)
- Full pkg ecosystem available (Nix has max compatibility)
- High power consumption acceptable

**Required Modules:**
```nix
imports = [
  "${self}/modules/nixos/base.nix"              # Core: users, networking, security
  "${self}/modules/nixos/hosts.nix"             # Hostname, sysctl
  "${self}/modules/nixos/persistence.nix"       # Impermanence setup (if enabled)
  "${self}/modules/nixos/clevis-initrd.nix"     # Encrypted boot (optional, recommended)
];
```

**Recommended:**
```nix
"${self}/modules/nixos/workstation.nix"        # Desktop environment, GNOME, etc.
"${self}/modules/nixos/hardening.nix"          # Security profiles
"${self}/users/martin/nixos.nix"               # User config
```

**Optional (as needed):**
- `modules/nixos/containers.nix` — For application containers
- `modules/nixos/apps.nix` — Desktop applications
- `modules/nixos/printing.nix` — CUPS support
- `modules/nixos/audio.nix` — Audio subsystem

**Devices:**
- **nixos-nvme** — Primary workstation (containers, development)
- **mac-mini** — Secondary workstation (RDP, monitoring, persona runtime)

**Current Status:** ✅ Both configured

---

### 🌐 Edge Hub Tier

**Purpose:** Central infrastructure services (caching, proxying, monitoring, containerized backends).

**Characteristics:**
- aarch64-linux (ARM, typically Raspberry Pi 5+)
- 4-8 GB RAM
- NVMe storage (PCIe hat) or SD card
- **Always online** (never powered down)
- Heavy container workload
- Serves as entrypoint for external traffic
- Cache/proxy responsibilities

**Required Modules:**
```nix
imports = [
  "${self}/modules/nixos/rpi5-node.nix"        # Tier bundle (includes base/headless/hosts)
  # rpi5-node.nix transitively imports:
  #   - base.nix (users, networking, security)
  #   - headless.nix (no GUI, minimal packages)
  #   - hosts.nix (hostname)
];
```

**Standard Additions:**
```nix
"./disko.nix"                                   # Declarative disk layout
"./secrets.nix"                                 # Device secrets
inputs.disko.nixosModules.disko                 # Disko module

# Presets for core services
inputs.nix-presets.nixosModules.caddy            # Reverse proxy
inputs.nix-presets.nixosModules.attic           # Binary cache
inputs.nix-presets.nixosModules.ntfy            # Push notifications
inputs.nix-presets.nixosModules.authelia        # SSO (if needed)
```

**Key Configuration:**
```nix
my = {
  boot.clevis-initrd = {
    enable = true;
    luksDevice = "core_crypt";    # Encrypted boot
    hostIp = "10.0.0.22";          # Static IP for initrd unlock
  };
  
  services.tang.enable = true;     # Tang NBDE server (part of Tang mesh)
  
  containers = { /* ... */ };      # Define hosted containers
};
```

**Devices:**
- **core-pi** — Primary hub (Caddy, Attic, ntfy, multiple AI services)

**Current Status:** ✅ Configured

---

### 🔧 Edge Node Tier

**Purpose:** Specialized compute nodes (AI/inference, storage, home automation, backup).

**Characteristics:**
- aarch64-linux (ARM SBC or small form factor)
- 2-8 GB RAM (depends on workload)
- Moderate storage (SSD for OS, additional HDDs for data nodes)
- May be powered down when not needed
- Single-purpose or dual-purpose (not central hub)
- Limited container hosting

**Required Modules:**
```nix
imports = [
  "${self}/modules/nixos/base.nix"              # Core
  "${self}/modules/nixos/headless.nix"          # No GUI
  "${self}/modules/nixos/hosts.nix"             # Hostname
  "${self}/modules/nixos/clevis-initrd.nix"     # Encrypted boot (recommended)
  "${self}/modules/nixos/persistence.nix"       # Impermanence (optional)
];
```

**Standard Additions:**
```nix
"./disko.nix"                                   # Declarative disk layout
"./secrets.nix"                                 # Device secrets
inputs.disko.nixosModules.disko

# Role-specific services (pick as needed)
inputs.nix-presets.nixosModules.monitoring      # Prometheus exporter
inputs.nix-presets.nixosModules.backup          # Restic backups
inputs.nix-presets.nixosModules.syncthing       # File sync (if data node)
```

**Optional:**
```nix
"${self}/modules/nixos/ai-hardening.nix"       # For AI nodes (orin-nano)
"${self}/modules/nixos/services/container-updater.nix"  # If hosting containers
```

**Key Configuration:**
```nix
my = {
  boot.clevis-initrd = {
    enable = true;
    luksDevice = "device_crypt";   # Encrypted boot
    hostIp = "10.0.0.XX";          # Static IP
  };
  
  services.tang.enable = true;     # Tang NBDE server (part of Tang mesh)
  
  # Role-specific config goes here
};
```

**Devices:**
- **orin-nano** — NVIDIA Jetson (AI/inference node)
- **nasbook** — QNAP NAS (storage hub, data services, backups)
- **hass-pi** — Home Assistant (home automation, not yet deployed)

**Current Status:** ⚠️ orin-nano ✅, nasbook ✅ (just converted), hass-pi ⏸️ (pending deployment)

---

### 📱 Mobile Tier

**Purpose:** Portable NixOS via Nix on Droid.

**Characteristics:**
- aarch64-linux (ARM mobile)
- Limited storage (internal only, 32-128 GB)
- Limited RAM (4-8 GB)
- Often offline
- No sudo/root access (Nix on Droid model)
- Configuration is local only

**Setup Pattern:**
- Minimal modules (nix, ca-certificates)
- No Clevis/encryption (mobile filesystem is already protected)
- No network services
- User-specific packages only

**Devices:**
- **phone** — Personal NixOS phone (via Nix on Droid)

**Current Status:** ⚠️ Minimal config (acceptable for mobile)

---

## Configuration Checklist

### Every Device Must Have:

- [ ] **Inventory entry** in `../inventory.nix`
  - `system` (x86_64-linux or aarch64-linux)
  - `deployType` (local, ssh, or other)
  - `tags` (tier, role, hardware)
  - `ip` and `netbirdIp` (if applicable)

- [ ] **Host directory** in `./hosts/<device-name>/`
  - `default.nix` (entry point, imports)
  - `secrets.nix` (even if minimal)
  - `disko.nix` (disk layout, not hardware-configuration.nix)
  - Optional: `network.nix`, `services.nix`, `hardware.nix`

- [ ] **Disk setup** via disko (not generated hardware-configuration.nix)
  ```nix
  imports = [ inputs.disko.nixosModules.disko ./disko.nix ];
  ```

- [ ] **Secrets structure** documented (sops-based)
  ```nix
  # ./secrets.nix should import sops secrets used by this device
  sops.secrets = {
    # device-specific secrets
  };
  ```

- [ ] **SSH keys** configured (if networked)
  - FIDO2 (primary)
  - YubiKey (backup)
  - Fleet key (ca-refresh, automation)

- [ ] **Network configuration** (if applicable)
  - Firewall rules
  - Interface assignment (LAN, NetBird mesh, etc.)
  - DNS (if special)

- [ ] **Services enabled/disabled** declaratively
  - Tang NBDE (if storage)
  - Monitoring node exporter (if monitored)
  - Container updater (if hosting containers)

---

## Device Configuration Template

Use this when adding a new device:

```nix
# hosts/<device-name>/default.nix
{
  inputs,
  self,
  myInventory,
  config,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
in
{
  imports = [
    # 1. Select tier bundle
    # For Workstation:
    "${self}/modules/nixos/workstation.nix"
    
    # For Edge Hub:
    "${self}/modules/nixos/rpi5-node.nix"
    
    # For Edge Node (manual composition):
    "${self}/modules/nixos/base.nix"
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"
    
    # 2. Device-specific setup
    inputs.disko.nixosModules.disko
    ./disko.nix
    "./secrets.nix"
    
    # 3. Tier-specific optional modules
    # "${self}/modules/nixos/ai-hardening.nix"     # AI nodes
    # "${self}/modules/nixos/services/container-updater.nix"  # Container hosts
  ];

  networking.hostName = "<device-name>";
  
  users.users.martin.openssh.authorizedKeys.keys = with keys.ssh; [
    yubikey
    fido2
    fido2-backup
  ];

  my = {
    boot.clevis-initrd = {
      enable = true;
      luksDevice = "<device_crypt>";
      hostIp = "<10.0.0.XX>";
      secretFile = "${inputs.nix-secrets}/initrd/<device>.jwe";
    };
    
    services.tang.enable = true;
  };
  
  system.stateVersion = "25.11";
}
```

---

## Deployment Strategy

### Local Deployment (nixos-nvme, phone)
- Configuration changes build + activate locally
- No network deployment needed
- Use: `sudo nixos-rebuild switch`

### SSH Deployment (everything else)
- Configuration pushed to device via SSH
- Built on device or substituted from cache
- Use: `just in <repo> nixos::deploy-<device>`
- Requires cache reachability for large devices

### Bootstrap (new device)
1. Create `hosts/<device-name>/` directory
2. Write `default.nix`, `disko.nix`, `secrets.nix`
3. Boot NixOS installer on device
4. Run `nixos-generate-config --show-hardware-config` (to understand hardware)
5. Use disko to partition: `disko-mount ./disko.nix`
6. Checkout nix-config repo at the Mount point
7. `sudo nixos-install --flake .#<device-name>`
8. Reboot, verify

---

## Current Fleet Status

| Device | Tier | Status | Config Debt |
|--------|------|--------|-------------|
| nixos-nvme | Workstation | ✅ Active | None |
| mac-mini | Workstation | ✅ Active | None |
| core-pi | Edge Hub | ✅ Active | Container pattern could be extracted |
| orin-nano | Edge Node | ✅ Active | None |
| nasbook | Edge Node | ✅ Active | ✅ Just converted to disko |
| hass-pi | Edge Node | ⏸️ Planned | None (config ready) |
| phone | Mobile | ⚠️ Minimal | None (acceptable for mobile) |

---

## Adding a New Device

1. **Inventory:** Add entry to `../inventory.nix` with appropriate tier tag
2. **Structure:** Create `hosts/<device-name>/` with the template above
3. **Disko:** Write disk layout for hardware (copy template from same-tier device)
4. **Secrets:** Create `secrets.nix` with sops decryption
5. **Deploy:** Follow bootstrap steps above
6. **Validate:** Verify SSH access, service startup, Tang mesh membership

---

## References

- **Tier bundles:** `modules/nixos/rpi5-node.nix` (Edge Hub), `modules/nixos/workstation.nix` (Workstation)
- **Base module:** `modules/nixos/base.nix` (required by all)
- **Inventory:** `inventory.nix` (master device registry)
- **Disko examples:** `hosts/core-pi/disko.nix`, `hosts/orin-nano/disko.nix`, `hosts/mac-mini/disko.nix`

---

**Last Updated:** 2026-08-17  
**Ref:** FLEET-INFRA-AUDIT.md (Gap #1 - Incomplete Tier Definitions)
