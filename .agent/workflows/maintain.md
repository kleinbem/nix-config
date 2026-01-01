---
description: Update flake inputs and clean up the system
---

# Workflow: Maintenance Loop

1. Update Flake Inputs
   `nix flake update`

2. Rebuild and Switch
   `sudo nixos-rebuild switch --flake .#$(hostname)`

// turbo
3. Garbage Collection (Delete old generations)
   `nix-collect-garbage -d`

// turbo
4. Optimise Store (Deduplicate)
   `nix-store --optimise`

1. Verify Disk Usage
   `df -h`
