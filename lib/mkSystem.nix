{
  nixpkgs,
  inputs,
  nixpak,
  self,
  ...
}:

{
  mkSystem =
    {
      hostname,
      user,
      system ? "x86_64-linux",
      extraModules ? [ ],
    }:
    nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs self; };
      modules = [
        # Host Specific Configuration
        ../hosts/${hostname}/default.nix

        # Core Components
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.home-manager
        inputs.lanzaboote.nixosModules.lanzaboote

        # NUR Overlay
        (_: {
          nixpkgs.overlays = [
            inputs.nur.overlays.default
            (_: prev: {
              stable = import inputs.nixpkgs-stable {
                inherit (prev) system;
                config.allowUnfree = true;
              };
            })
          ];
        })

        # User Configuration
        ../users/${user}/nixos.nix

        # Home Manager Configuration
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = { inherit nixpak inputs; };
            backupFileExtension = "backup";
            users.${user} = import ../users/${user}/home.nix;
          };
        }
      ]
      ++ extraModules;
    };
}
