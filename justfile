# nix-config Justfile
#
# Recipes that operate ON the nix-config flake itself: building, evaluating,
# deploying, host operations. Meta-workspace concerns (cross-repo git, devshell
# entry, workspace-wide audits) stay in the meta-workspace justfile one level up.
#
# Run from anywhere inside nix-config. `just --list` for the full hub.

import '.just/common.just'

# --- Modules ---
mod nixos       '.just/nixos.just'
mod android     '.just/android.just'
mod ai          '.just/ai.just'
mod dev         '.just/dev.just'
mod deployment  '.just/deployment.just'
mod maintenance '.just/maintenance.just'
mod personas    '.just/personas.just'

# Per-host operations (ping/shell/logs/gui)
mod orin        '.just/orin.just'
mod nasbook     '.just/nasbook.just'
mod core-pi     '.just/core-pi.just'
mod hass-pi     '.just/hass-pi.just'

# --- Top-level shortcuts (muscle memory) ---

[group("Main")]
default:
    @just --list

[group("Main")]
switch *args="":
    @just nixos::switch {{args}}
