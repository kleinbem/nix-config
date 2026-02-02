{ inputs, ... }:
{
  # Overlays
  nixpkgs.overlays = [
    inputs.nur.overlays.default
    inputs.nix-packages.overlays.default
    (_self: super: {
      stable = import inputs.nixpkgs-stable {
        inherit (super) system;
        config.allowUnfree = true;
      };
    })
  ];

  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs;
      inherit (inputs) nixpak;
    };
    backupFileExtension = "backup";
  };
}
