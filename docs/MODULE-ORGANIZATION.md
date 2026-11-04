# Module Organization & Import Patterns

This document explains how NixOS modules are organized in this fleet and when to use each import strategy.

---

## Module Layers

### Layer 1: Foundation (Imported by Everyone)

These modules are **required** and imported by every device configuration:

| Module | Purpose | Used By |
|--------|---------|---------|
| `base.nix` | Users, networking, SSH, sops, home-manager, core Nix settings | Every device (directly or via a bundle) |
| `hosts.nix` | Hostname, sysctl tuning | Every device |

### Layer 2: Tier Bundles / Aggregators (Select One)

| Bundle | Purpose | Includes | Used By |
|--------|---------|----------|---------|
| **`workstation-bundle.nix`** | Workstation feature set (GUI, kernel tuning, security, printing, Android dev, …) | kernel, audio, desktop, security/audit, printing, android, ai-hardening, snapper, … (16 modules) | nixos-nvme, via `default.nix` |
| **Edge Hub** (`rpi5-node.nix`) | Infrastructure hub | base, headless, hosts, persistence, RPi hardware, Tang | core-pi, hass-pi |
| **Mobile** (minimal) | Nix on Droid | base, ca-certs | phone |

There is deliberately **no bundle for Pattern B devices** (mac-mini, nasbook, orin-nano) — each hand-selects `base.nix` + `headless.nix` + `hosts.nix` plus whatever else it needs. See Pattern B below for why.

### Layer 3: Device-Specific Configs

Each device has its own directory with custom setup:

```
hosts/<device-name>/
├── default.nix           # Entry point (imports)
├── disko.nix             # Disk layout
├── secrets.nix           # sops decryption
├── network.nix           # (optional) Firewall, interfaces
├── containers.nix        # (optional) LXD/OCI containers
├── services.nix          # (optional) Service config
└── README.md             # (optional) Device notes
```

---

## Import Patterns

### Pattern A: Tier Bundle (Recommended for New Edge Devices)

**When:** Setting up an Edge Hub device (RPi5-class infrastructure node)

**How:**
```nix
{
  imports = [
    "${self}/modules/nixos/rpi5-node.nix"     # Tier bundle (imports base+headless+persistence+...)

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

**Devices using this:** core-pi, hass-pi (both via `rpi5-node.nix`)

---

### Pattern B: Selective Imports (Edge Nodes + non-desktop workstations)

**When:** Device needs a custom mix of modules — an edge node that isn't RPi5-class, or a workstation-class box that doesn't want the full `workstation-bundle.nix` feature set

**How:**
```nix
{
  imports = [
    # Foundation
    "${self}/modules/nixos/base.nix"
    "${self}/modules/nixos/headless.nix"      # or desktop.nix directly, like mac-mini
    "${self}/modules/nixos/hosts.nix"

    # Explicit additions (no bundle)
    "${self}/modules/nixos/persistence.nix"
    "${self}/modules/nixos/container-host.nix"

    # Device-specific
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./secrets.nix
  ];
}
```

**Benefit:** Explicit about what's imported, easy to see and modify — and avoids pulling in features the device has no use for (e.g. `workstation-bundle.nix`'s kernel tuning, printing, and Android-dev modules don't belong on a headless container host).

**Devices using this:** mac-mini, nasbook, orin-nano — each selects `base.nix` + `headless.nix` (mac-mini also layers `desktop.nix` directly, for GNOME Remote Desktop) + `hosts.nix`, then hand-picks the rest.

**Note:** mac-mini's own comment explains why it doesn't import `workstation-bundle.nix` even though it has a desktop component:
> "deliberately doesn't import default.nix (pulls in unrelated things like kernel.nix/security/)"

---

### Pattern C: Aggregator Import (nixos-nvme only)

**When:** The single primary desktop workstation that wants the full feature set

**How:**
```nix
{
  imports = [
    inputs.nix-hardware.nixosModules.nixos-nvme
    inputs.nix-hardware.nixosModules.intel-compute
    "${self}/modules/nixos/workstation.nix"   # Workstation-tier overlays/hardening/avahi
    "${self}/modules/nixos/hosts.nix"
    "${self}/modules/nixos/default.nix"       # base.nix + workstation-bundle.nix

    # Device-specific
    "${self}/modules/nixos/persistence.nix"
    "${self}/modules/nixos/apps.nix"
    inputs.disko.nixosModules.disko
  ];
}
```

**How it works:** `default.nix` is a thin two-line wrapper — `base.nix` + `workstation-bundle.nix`. `workstation-bundle.nix` is the actual aggregator: it bundles 16 workstation-specific modules (kernel tuning, audio, desktop, security/audit, printing, 3D printing, Android dev, ai-hardening, ananicy, snapper, clevis-initrd, initrd-fan, scripts, tang). Each imported module defines optional features gated by `my.*` options, most off by default; the device config enables what it needs.

**Benefit:** One import gets the full workstation feature set; `workstation-bundle.nix` itself is a named, documented, single place to see what that set is (as opposed to the old flat 19-import list `default.nix` used to be — see "History" below).

**Devices using this:** nixos-nvme only

---

## Module Dependency Graph

```
base.nix (core, all devices — directly or via a bundle)
├── options.nix (my.* schema)
├── sops-nix
├── home-manager
├── core.nix (Nix settings, locale, kernel-tuning baselines)
└── auto-upgrade.nix (option only)

workstation-bundle.nix (Pattern C internals — 16 modules)
├── kernel.nix, audit.nix, security/, audio.nix
├── desktop.nix, firejail.nix, users.nix, snapper.nix
├── printing.nix, threed-printing.nix, android.nix
├── ai-hardening.nix, ananicy.nix
├── clevis-initrd.nix, initrd-fan.nix
├── scripts.nix
└── services/tang.nix

default.nix (Pattern C entry point)
├── base.nix
└── workstation-bundle.nix

rpi5-node.nix (Edge Hub tier bundle — Pattern A)
├── base.nix
├── headless.nix
├── hosts.nix
├── persistence.nix
├── clevis-initrd.nix, rpi-eeprom.nix, rpi-direct-boot.nix
└── nix-hardware rpi5 + disko

headless.nix (extra bits for headless/remote nodes — RPi5, NASbook, routers)
└── (imported directly by Pattern B hosts alongside base.nix)
```

---

## When to Use Each Pattern

### Use Pattern A (Tier Bundle)
✅ **DO use for:**
- New Edge Hub devices (RPi5-class infrastructure nodes)
- Simple, clear setup path with recommended defaults

❌ **Don't use for:**
- Workstations (`rpi5-node.nix` is RPi5-hardware-specific)
- Devices that need a custom, narrower feature mix

**Devices:** core-pi, hass-pi

---

### Use Pattern B (Selective Imports)
✅ **DO use for:**
- Edge nodes that aren't RPi5-class, or need an unusual module mix (orin-nano, nasbook)
- A workstation-class device that wants only *some* of `workstation-bundle.nix`'s features (mac-mini)
- When you want explicit control over exactly what's imported

❌ **Don't use for:**
- Simple RPi5 edge devices (Pattern A is clearer and less typing)
- The primary desktop workstation that genuinely wants the full feature set (Pattern C is one import instead of fifteen)

**Devices:** mac-mini, nasbook, orin-nano

---

### Use Pattern C (Aggregator)
✅ **DO use for:**
- A workstation that wants the full `workstation-bundle.nix` feature set in one import

❌ **Don't use for:**
- Edge devices (overkill, includes unrelated modules)
- A workstation that wants only a subset of the bundle — use Pattern B and import `workstation-bundle.nix`'s underlying modules selectively instead

**Devices:** nixos-nvme only

---

## Common Gotchas

### Gotcha 1: "I imported Module X but its options aren't available"

**Problem:** Module is not imported.

**Solution:** Check `imports` in your `default.nix`. If the module is only reachable via `workstation-bundle.nix` (Pattern C) and your device doesn't import that, import the module explicitly.

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

**Problem:** Feature is defined in a module not imported by your device (nixos-nvme gets the full `workstation-bundle.nix`; most other hosts don't).

**Solution:** Check which device has it working, look at its imports, add that module to yours.

**Example:**
```bash
# Find where audio is defined
grep -r "services.pipewire" hosts/nixos-nvme/*.nix
# → modules/nixos/audio.nix (reached via workstation-bundle.nix)

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

## History

The three-pattern layout used to include a real pain point: `default.nix` (Pattern C) was a flat, ~19-module list with no name for "the workstation feature set" — hard to trace what nixos-nvme actually imported. That was fixed 2026-08-28: the flat list was extracted into `workstation-bundle.nix` (16 modules, documented), and `default.nix` became the two-line `base.nix` + `workstation-bundle.nix` wrapper it is today.

Pattern B devices (mac-mini, nasbook, orin-nano) were **not** migrated onto `workstation-bundle.nix` and don't need to be — each needs a narrower, different subset of features than the bundle provides (e.g. mac-mini wants `desktop.nix` for remote GUI access but none of the kernel-tuning/printing/Android-dev modules), so selective imports remain the right fit there. `workstation-bundle.nix`'s own header documents it as optionally importable by a Pattern B device that *does* want the whole set, but no current device does.

---

## Files to Understand

**Module structure:**
- `modules/nixos/base.nix` — Required foundation
- `modules/nixos/default.nix` — Pattern C entry point (`base.nix` + `workstation-bundle.nix`)
- `modules/nixos/workstation-bundle.nix` — The 16-module workstation feature set
- `modules/nixos/rpi5-node.nix` — Raspberry Pi 5 tier bundle (Pattern A)

**Device examples:**
- `hosts/nixos-nvme/default.nix` — Pattern C (aggregator)
- `hosts/mac-mini/default.nix` — Pattern B (selective, explicit avoidance of the bundle)
- `hosts/core-pi/default.nix` — Pattern A (tier bundle)

---

## Summary Table

| Pattern | Typical Tier | Clarity | Devices |
|---------|------|---------|-----------------|
| **A** (Tier Bundle) | Edge Hub | ⭐⭐⭐ Explicit | core-pi, hass-pi |
| **B** (Selective) | Edge Node / partial-workstation | ⭐⭐⭐ Explicit | mac-mini, nasbook, orin-nano |
| **C** (Aggregator) | Primary workstation | ⭐⭐⭐ Explicit (bundle is named + documented) | nixos-nvme |

**Recommendation:** Pattern A for a new RPi5 edge device; Pattern B for anything with a narrower or unusual feature mix; Pattern C only fits the single primary desktop workstation.

---

**Last Updated:** 2026-09-11
