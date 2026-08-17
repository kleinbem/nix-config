# Module Organization & Import Patterns

**Status:** Current patterns documented; refactor deferred (low urgency).

This document explains how NixOS modules are organized in this fleet and when to use each import strategy.

---

## Module Layers

### Layer 1: Foundation (Imported by Everyone)

These modules are **required** and imported by every device configuration:

| Module | Purpose | Used By |
|--------|---------|---------|
| `base.nix` | Users, networking, SSH, basic security | Every device |
| `hosts.nix` | Hostname, sysctl tuning | Every device |

### Layer 2: Tier Bundles (Select One)

Choose a tier bundle based on device type:

| Bundle | Purpose | Includes | Used By |
|--------|---------|----------|---------|
| **Workstation** (`workstation.nix`) | Desktop tier | base, desktop, audio, etc. | nixos-nvme |
| **Edge Hub** (`rpi5-node.nix`) | Infrastructure hub | base, headless, Tang | core-pi |
| **Edge Node** (selective) | Specialized compute | base, headless (+ selective additions) | orin-nano, nasbook, hass-pi |
| **Mobile** (minimal) | Nix on Droid | base, ca-certs | phone |

### Layer 3: Device-Specific Configs

Each device has its own directory with custom setup:

```
hosts/<device-name>/
├── default.nix           # Entry point (imports)
├── disko.nix            # Disk layout
├── secrets.nix          # sops decryption
├── network.nix          # (optional) Firewall, interfaces
├── containers.nix       # (optional) LXD/OCI containers
├── services.nix         # (optional) Service config
└── README.md            # (optional) Device notes
```

---

## Import Patterns

### Pattern A: Tier Bundle (Recommended for New Devices)

**When:** Setting up an Edge Hub or Edge Node

**How:**
```nix
{
  imports = [
    "${self}/modules/nixos/rpi5-node.nix"     # Tier bundle (imports base+headless)
    
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./secrets.nix
    
    # Selective additions beyond the bundle
    inputs.nix-presets.nixosModules.monitoring
    inputs.nix-presets.nixosModules.backup
  ];
}
```

**Benefit:** Clear tier selection, no surprises, minimal imports.

**Devices using this:** core-pi (via rpi5-node.nix)

---

### Pattern B: Selective Imports (Cleanest for Complex Devices)

**When:** Device needs custom mix of modules (like mac-mini, nixos-nvme)

**How:**
```nix
{
  imports = [
    # Tier foundation
    "${self}/modules/nixos/base.nix"
    "${self}/modules/nixos/headless.nix"      # or desktop.nix
    
    # Explicit additions (no aggregator)
    "${self}/modules/nixos/persistence.nix"
    "${self}/modules/nixos/desktop.nix"       # GNOME, GUI apps
    "${self}/modules/nixos/audio.nix"         # Sound system
    
    # Device-specific
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./secrets.nix
  ];
}
```

**Benefit:** Explicit about what's imported, easy to see and modify.

**Devices using this:** mac-mini (explicitly avoids default.nix)

**Note:** mac-mini comment explains why:
> "deliberately doesn't import default.nix (pulls in unrelated things like kernel.nix/security/)"

---

### Pattern C: Aggregator Import (Used by Workstation Tier Only)

**When:** Workstation tier device that needs everything

**How:**
```nix
{
  imports = [
    inputs.nix-hardware.nixosModules.nixos-nvme
    "${self}/modules/nixos/workstation.nix"   # Workstation tier bundle
    "${self}/modules/nixos/default.nix"       # Full aggregator
    
    # Device-specific overrides
    ./ai.nix
    ./containers.nix
  ];
}
```

**How it works:**
- `default.nix` imports ~19 modules (kernel, audio, desktop, printing, android, ai-hardening, etc.)
- Each module defines optional features gated by `my.*` options
- Default state: most features OFF (e.g., `my.desktop.enable = false`)
- Device config enables what it needs (e.g., `my.desktop.gnome.enable = true`)

**Benefit:** Convenient for complex devices with many features.

**Drawback:** Less explicit; harder to trace what's actually imported (see module X, but where is it defined?).

**Devices using this:** nixos-nvme only

---

## Module Dependency Graph

```
base.nix (core, all devices)
├── users.nix
├── networking.nix
├── security/ssh.nix
└── boot.nix (kernel modules, etc.)

workstation.nix (x86_64 desktops)
├── base.nix
├── desktop.nix (GNOME, GUI apps)
├── audio.nix
├── hardening.nix
└── apps.nix

rpi5-node.nix (Raspberry Pi tier bundle)
├── base.nix
├── headless.nix
└── hosts.nix

default.nix (workstation aggregator - import cautiously)
├── base.nix
├── kernel.nix
├── audio.nix
├── desktop.nix
├── printing.nix
├── android.nix
├── ai-hardening.nix
├── security/ (multiple modules)
└── ... 11 more ...
```

---

## When to Use Each Pattern

### Use Pattern A (Tier Bundle)
✅ **DO use for:**
- New Edge Hub or Edge Node devices
- Simple, clear setup path
- Want recommended defaults

❌ **Don't use for:**
- Workstations (no workstation tier bundle exists yet)
- Devices that need custom feature mix

**Devices:** core-pi (Edge Hub), orin-nano, nasbook, hass-pi (Edge Nodes)

---

### Use Pattern B (Selective Imports)
✅ **DO use for:**
- Workstations (nixos-nvme, mac-mini)
- Devices with unusual feature combinations
- When you want explicit control

❌ **Don't use for:**
- Simple edge devices (Pattern A is clearer)

**Devices:** mac-mini (explicitly does this to avoid unrelated modules)

---

### Use Pattern C (Aggregator)
✅ **DO use for:**
- nixos-nvme (primary workstation with many features)
- Complex feature combinations that benefit from bundling

❌ **Don't use for:**
- Edge devices (overkill, includes unrelated modules)
- New devices (unclear what's being imported)

**Devices:** nixos-nvme only

---

## Common Gotchas

### Gotcha 1: "I imported Module X but its options aren't available"

**Problem:** Module is not imported.

**Solution:** Check `imports` in your `default.nix`. If the module is in `default.nix` but your device doesn't import `default.nix`, you need to import the module explicitly.

**Example:**
```nix
# ❌ This won't work (audio module not imported)
imports = [ "${self}/modules/nixos/base.nix" ];
audio.jabra.preferred = true;  # Error: undefined option

# ✅ Fix: Import audio module
imports = [
  "${self}/modules/nixos/base.nix"
  "${self}/modules/nixos/audio.nix"  # Now audio options available
];
audio.jabra.preferred = true;
```

---

### Gotcha 2: "Feature X works on nixos-nvme but not on my device"

**Problem:** Feature is defined in a module not imported by your device.

**Solution:** Check which device has it working, look at its imports, add that module to yours.

**Example:**
```bash
# Find where audio is defined
grep -r "services.pipewire" hosts/nixos-nvme/*.nix
# → modules/nixos/audio.nix

# Add to your device
imports = [ "${self}/modules/nixos/audio.nix" ];
```

---

### Gotcha 3: "Module options are defined but not taking effect"

**Problem:** Module is imported, but feature is disabled by default (gated by `enable` option).

**Solution:** Enable the feature explicitly.

**Example:**
```nix
# audio.nix imports fine, but sound doesn't work
# Check what's defined:
grep -r "audio.enable" modules/nixos/audio.nix
# → my.audio.enable = false;  (default, feature disabled)

# Enable it:
my.audio.enable = true;
```

---

## Recommended Refactoring (Deferred)

**Problem (Current State):** Three import patterns coexist, which confuses new maintainers.

**Proposed Solution:**
1. Create `workstation-bundle.nix` (explicit tier bundle for Pattern B/C devices)
2. Update Pattern C docs (explain it's workstation-specific)
3. Recommend Pattern A (tier bundles) for new devices
4. Don't refactor existing configs (risk of breakage, YubiKey signed commits needed)

**Effort:** 3-4 hours (refactor + testing)  
**Urgency:** Low (works as-is, documentation addresses confusion)  
**When:** After you're back from vacation and can sign commits

---

## Files to Understand

**Module structure:**
- `modules/nixos/base.nix` — Required foundation
- `modules/nixos/default.nix` — Aggregator (workstation-specific)
- `modules/nixos/rpi5-node.nix` — Raspberry Pi tier bundle

**Device examples:**
- `hosts/nixos-nvme/default.nix` — Pattern C (aggregator)
- `hosts/mac-mini/default.nix` — Pattern B (selective, explicit avoidance of aggregator)
- `hosts/core-pi/default.nix` — Pattern A (tier bundle)

**Tier bundles:**
- `modules/nixos/workstation.nix` — Workstation tier
- `modules/nixos/headless.nix` — Headless tier (no GUI)
- `modules/nixos/rpi5-node.nix` — Raspberry Pi tier

---

## Summary Table

| Pattern | Tier | Clarity | Overhead | Example Device |
|---------|------|---------|----------|-----------------|
| **A** (Tier Bundle) | Edge | ⭐⭐⭐ Explicit | Low | core-pi |
| **B** (Selective) | Workstation | ⭐⭐⭐ Explicit | Low | mac-mini |
| **C** (Aggregator) | Workstation | ⭐⭐ Implicit | Medium | nixos-nvme |

**Recommendation:** Use Pattern A (Tier Bundle) for new devices.

---

**Last Updated:** 2026-08-17  
**Ref:** FLEET-INFRA-AUDIT.md (Gap #2 - Module Aggregator Dependency Problem)
