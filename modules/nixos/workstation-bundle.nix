# Workstation Bundle
#
# Aggregates all workstation-specific modules (GUI, development, multimedia, etc.)
# for use in Pattern C (full aggregator) or Pattern B (selective import) setups.
#
# Usage Option 1 — Full aggregation (Pattern C):
#   imports = [ "${self}/modules/nixos/workstation-bundle.nix" ];
#
# Usage Option 2 — Selective import (Pattern B, like mac-mini):
#   imports = [
#     "${self}/modules/nixos/base.nix"
#     "${self}/modules/nixos/workstation-bundle.nix"
#     # ... device-specific overrides
#   ];
#
# What this includes:
#   - Kernel configuration (performance, security)
#   - Audio system (PipeWire)
#   - Desktop environment (GNOME, X11)
#   - Printing and 3D printing
#   - Security hardening (AppArmor, audit)
#   - Development tools setup
#   - Android development
#   - And more (see imports below)
#
# Note: Assumes base.nix is already imported separately. This bundle only adds
# workstation-specific features on top of the base tier.

{ ... }:
{
  imports = [
    # Tier foundation (must be imported first)
    # base.nix should be imported BEFORE this in the device config

    # Kernel & Performance
    ./kernel.nix

    # Security & Audit
    ./audit.nix
    ./security

    # Audio & Media
    ./audio.nix

    # Desktop Environment
    ./desktop.nix
    ./firejail.nix

    # User Setup
    ./users.nix

    # System Maintenance
    ./snapper.nix

    # Hardware Support
    ./printing.nix
    ./threed-printing.nix
    ./android.nix

    # AI/Performance
    ./ai-hardening.nix
    ./ananicy.nix

    # Boot & Initialization
    ./clevis-initrd.nix
    ./initrd-fan.nix

    # System Scripts & Utilities
    ./scripts.nix

    # Services
    ./services/tang.nix
  ];
}
