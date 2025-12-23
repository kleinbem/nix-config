{
  nixpkgs,
  inputs,
  nixpak,
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
      specialArgs = { inherit inputs; };
      modules = [
        # Host Specific Configuration
        ../hosts/${hostname}/default.nix

        # Core Components
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.home-manager

        # Home Manager Configuration
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = { inherit nixpak; };
            backupFileExtension = "backup";
            users.${user} = import ../hosts/${hostname}/home.nix;
          };
        }
      ]
      ++ extraModules;
    };
}
