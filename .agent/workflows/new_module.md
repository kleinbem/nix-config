---
description: Create a new scalable NixOS or Home Manager module
---

# Workflow: Create New Module

1. Determine the scope
   - Is this system-level? -> `modules/nixos/<category>/<name>`
   - Is this user-level? -> `modules/home-manager/<category>/<name>`

2. Create the directory and default.nix
   `mkdir -p modules/<scope>/<category>/<name>`
   `touch modules/<scope>/<category>/<name>/default.nix`

3. Populate with standard template
   Write the following boilerplate to the new file:

   ```nix
   { pkgs, config, lib, ... }:
   with lib;
   let
     cfg = config.path.to.module;
   in
   {
     options.path.to.module = {
       enable = mkEnableOption "Enable <name>";
     };

     config = mkIf cfg.enable {
       # configuration here
     };
   }
   ```

4. Register the module
   Ensure the parent `default.nix` (e.g., `modules/nixos/default.nix`) imports this new folder/file.
