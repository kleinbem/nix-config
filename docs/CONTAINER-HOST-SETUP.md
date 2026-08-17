# Container Host Setup Guide

**Status:** Module available; existing devices can adopt incrementally  
**Created:** 2026-08-17

This document explains how to set up a device that hosts LXD containers, using the new `container-host.nix` module for simplified, reusable configuration.

---

## Quick Start

### Minimal Container Host Setup

```nix
# hosts/<device-name>/default.nix

{
  inputs,
  self,
  myInventory,
  config,
  ...
}:
{
  imports = [
    # Tier bundle (base + headless + hosts)
    "${self}/modules/nixos/rpi5-node.nix"
    
    # Container host support
    "${self}/modules/nixos/container-host.nix"
    
    # Device-specific
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./secrets.nix
    
    # Container presets (pick as needed)
    inputs.nix-presets.nixosModules.caddy
    inputs.nix-presets.nixosModules.attic
    inputs.nix-presets.nixosModules.ntfy
  ];

  networking.hostName = "<device-name>";

  # Enable container hosting
  my.container-host = {
    enable = true;
    subnet = "10.85.48.0/24";        # Change per device
    hostAddress = "10.85.48.1";
    excludeFromUpdater = [ "attic" "caddy" ];  # Bootstrap-critical services
  };

  # Declare containers (module handles networking, persistence, auto-update)
  my.containers = {
    caddy = {
      enable = true;
      ip = "${myInventory.network.nodes.caddy.ip}/24";
      hostDataDir = "/var/lib/caddy";
      memoryLimit = "512M";
    };

    attic = {
      enable = true;
      ip = "${myInventory.network.nodes.attic.ip}/24";
      hostDataDir = "/var/lib/images/attic";
    };

    ntfy = {
      enable = true;
      ip = "${myInventory.network.nodes.ntfy.ip}/24";
    };

    # Add more containers as needed
  };

  system.stateVersion = "25.11";
}
```

---

## What the Module Provides

### Networking
- ✅ Container bridge setup (cbr0 by default)
- ✅ Host bridge IP on container subnet
- ✅ Firewall rules for container traffic
- ✅ Inter-container communication

### Persistence
- ✅ Automatic persistence for all `hostDataDir` locations
- ✅ Works with impermanent hosts (e.g., core-pi)
- ✅ Survives reboots, clears on OS updates

### Container Auto-Update (ADR 002)
- ✅ Nightly container refresh from CI manifest
- ✅ Eval-free on edge devices (no NixOS rebuild needed)
- ✅ Smart exclusions (keep bootstrap-critical services in host closure)
- ✅ Activation order (attic activates last to avoid deadlock)

### Systemd Orchestration
- ✅ Dependency management (network before containers)
- ✅ Readiness checks (wait for cache availability)

---

## Configuration Options

### `my.container-host.enable`
Enables container host support.

```nix
my.container-host.enable = true;
```

### `my.container-host.subnet`
**Required.** Container subnet in CIDR notation.

```nix
my.container-host.subnet = "10.85.48.0/24";  # core-pi
my.container-host.subnet = "10.85.50.0/24";  # mac-mini
my.container-host.subnet = "10.85.47.0/24";  # nasbook
```

### `my.container-host.hostAddress`
**Required.** Host bridge IP (must be in subnet).

```nix
my.container-host.hostAddress = "10.85.48.1";
```

### `my.container-host.bridge`
Container bridge name (default: cbr0).

```nix
my.container-host.bridge = "cbr0";  # Standard
```

### `my.container-host.excludeFromUpdater`
Containers to keep in host closure (not auto-updated). Use for bootstrap-critical services (cache, proxy, authentication).

```nix
my.container-host.excludeFromUpdater = [
  "attic"       # Binary cache (deadlock if decoupled)
  "caddy"       # Reverse proxy (deadlock if decoupled)
  "crowdsec"    # Security blocker (must start at boot)
];
```

### `my.container-host.enablePersistence`
Enable impermanence support (default: true).

```nix
my.container-host.enablePersistence = true;
```

---

## Container Declaration Pattern

Each container in `my.containers.<name>` can have:

```nix
my.containers.caddy = {
  enable = true;                                    # Required
  ip = "${myInventory.network.nodes.caddy.ip}/24"; # Required: IPv4 address
  
  # Optional
  hostDataDir = "/var/lib/caddy";                   # Auto-persisted
  memoryLimit = "512M";                             # Memory cap
  domain = "caddy.example.com";                     # If needed
  auth = true;                                      # SSO gating
  secretsFile = config.sops.secrets.caddy_env.path; # Secrets
  
  # Container-specific options (defined in nix-presets)
  # Check the preset module for available options
};
```

---

## Device Comparison

### Before (Old Pattern — Manual Setup)

```nix
# hosts/core-pi/default.nix (150+ lines)

my = {
  network = { subnet = "10.85.48.0/24"; hostAddress = "10.85.48.1"; };
  
  containers = {
    caddy = { enable = true; ip = "..."; hostDataDir = "/var/lib/caddy"; };
    attic = { enable = true; ip = "..."; hostDataDir = "/var/lib/images/attic"; };
    # ... 6 more containers
  };
  
  services.container-updater = {
    enable = true;
    containers = lib.subtractLists ["attic" "caddy" "crowdsec"] (/* compute all */);
  };
};

environment.persistence."/nix/persist" = {
  directories = [ "/var/lib/caddy" "/var/lib/images/attic" /* ... */ ];
};

systemd.services = { /* custom service deps */ };
networking.firewall = { extraForwardRules = ''...'' };
```

### After (New Pattern — Using Module)

```nix
# hosts/new-container-host/default.nix (30 lines)

imports = [
  "${self}/modules/nixos/rpi5-node.nix"
  "${self}/modules/nixos/container-host.nix"  # ← Handles ~50 lines of boilerplate
  ./disko.nix
];

my.container-host = {
  enable = true;
  subnet = "10.85.48.0/24";
  hostAddress = "10.85.48.1";
  excludeFromUpdater = [ "attic" "caddy" "crowdsec" ];
};

my.containers = {
  caddy = { enable = true; ip = "..."; hostDataDir = "/var/lib/caddy"; };
  attic = { enable = true; ip = "..."; hostDataDir = "/var/lib/images/attic"; };
  # ... more containers
};
```

**Benefit:** ~120 lines → ~30 lines of config. Module handles:
- Container persistence
- Firewall rules
- Container-updater orchestration
- Systemd dependencies
- Network setup

---

## Migration Guide (For Existing Container Hosts)

If you have an existing container host (like core-pi), you can incrementally adopt this module:

### Step 1: Add Module Import
```nix
imports = [
  # ... existing imports ...
  "${self}/modules/nixos/container-host.nix"  # ADD THIS
];
```

### Step 2: Extract Container Config
```nix
my.container-host = {
  enable = true;
  subnet = "10.85.48.0/24";           # Copy from existing my.network.subnet
  hostAddress = "10.85.48.1";         # Copy from existing my.network.hostAddress
  excludeFromUpdater = [ "attic" "caddy" "crowdsec" ];
};

# Remove these sections (module handles them now):
# - my.network = { ... }  ← REMOVE
# - environment.persistence = { ... }  ← REMOVE (auto-calculated)
# - services.container-updater = { ... }  ← REMOVE (module configures)
# - networking.firewall.extraForwardRules = { ... }  ← REMOVE
```

### Step 3: Test
```bash
nixos-rebuild build
# Verify no errors
```

### Step 4: Activate
```bash
sudo nixos-rebuild switch
```

---

## Best Practices

### 1. Persistence Strategy
- Always set `hostDataDir` for containers that need state
- Module auto-persists everything listed
- For stateless containers (statix, ntfy), omit `hostDataDir`

### 2. Bootstrap-Critical Services
- Identify services that create circular dependencies:
  - **Attic** (binary cache for container images — deadlock if auto-updated)
  - **Caddy** (reverse proxy for public access — deadlock if auto-updated)
  - **Authentication** (SSO proxy — deadlock if auto-updated)
- Add to `excludeFromUpdater` list
- Keep these in host closure

### 3. Memory Limits
- Set `memoryLimit` for resource-intensive containers
- Default (no limit) may cause memory pressure on small devices

### 4. Container Order
- Use `my.containers.<name>.enable` to selectively enable/disable
- Module auto-computes auto-update container list

---

## Troubleshooting

### "Undefined option: my.container-host"
**Fix:** Add `imports = [ "${self}/modules/nixos/container-host.nix" ];`

### "Container not persisting across reboots"
**Fix:** Ensure `hostDataDir` is set for the container:
```nix
my.containers.myapp = {
  enable = true;
  ip = "...";
  hostDataDir = "/var/lib/images/myapp";  # ← Required for persistence
};
```

### "Container auto-update deadlock"
**Fix:** Add container to `excludeFromUpdater`:
```nix
my.container-host.excludeFromUpdater = [ "my-cache-container" ];
```

### "Containers can't reach external network"
**Fix:** Check firewall rules are applied:
```bash
sudo nft list ruleset | grep cbr0
# Should show accept rules for bridge traffic
```

---

## Architecture Notes (ADR 002)

The container auto-update strategy decouples container lifecycle from NixOS host generations:

1. **Host Rebuild** — Updates NixOS system, rebuilds bootstrap-critical containers
2. **Container Manifest** — CI publishes new container images to cache
3. **Nightly Update** — `container-updater.service` refreshes non-critical containers from cache (eval-free)
4. **Activation Order** — Attic activates last (so others can pull their images)

This allows edge devices to refresh containers without rebuilding the entire NixOS system locally.

---

## Files & References

- **Module:** `modules/nixos/container-host.nix`
- **ADR:** `docs/ADR-*.md` (container decoupling strategy)
- **Example:** `hosts/core-pi/default.nix` (before migration)
- **Tier Bundle:** `modules/nixos/rpi5-node.nix` (use with container-host)

---

## Future Enhancements

### 1. Container Preset Bundles
Create `container-host-caddy-attic.nix` preset that auto-imports Caddy + Attic presets + proper exclusions.

### 2. NAT/Port Forwarding
Add automatic port forwarding rules (e.g., NetBird → Caddy → containers).

### 3. Container Monitoring
Auto-add container exporters to Prometheus scrape config.

---

**Last Updated:** 2026-08-17  
**Status:** Module stable, ready for adoption  
**Adoption Effort:** Low (incremental, non-breaking)
