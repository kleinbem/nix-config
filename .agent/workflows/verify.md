---
description: Perform a dry-run build to verify configuration validity
---

# Workflow: Verification

1. Navigate to the project root
   `cd $(git rev-parse --show-toplevel)`

2. Check the flake for syntax errors
   `nix flake check`

// turbo
3. Perform a dry-run instantiation of the system
   `nix eval .#nixosConfigurations.$(hostname).config.system.build.toplevel.outPath`

1. (Optional) Show the derivation that would be built
   `nix show-derivation .#nixosConfigurations.$(hostname).config.system.build.toplevel`
