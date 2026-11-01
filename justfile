# nix-config Justfile: building, evaluating, deploying, host operations.
# Cross-repo concerns live in the conductor justfile one level up.

import '.just/common.just'

# --- Modules ---
mod nixos       '.just/nixos.just'
mod android     '.just/android.just'
mod ai          '.just/ai.just'
mod dev         '.just/dev.just'
mod deployment  '.just/deployment.just'
mod access      '.just/access.just'
mod maintenance '.just/maintenance.just'
mod personas    '.just/personas.just'
mod containers  '.just/containers.just'

# Per-host operations (ping/shell/logs/gui)
mod orin        '.just/orin.just'
mod nasbook     '.just/nasbook.just'
mod core-pi     '.just/core-pi.just'
mod hass-pi     '.just/hass-pi.just'
mod mac-mini    '.just/mac-mini.just'

# --- Top-level shortcuts (muscle memory) ---

[group("Main")]
default:
    @just --list

[group("Main")]
switch *args="":
    @just nixos::switch {{args}}

[group("Main")]
apply *args="":
    @just dev::apply {{args}}
