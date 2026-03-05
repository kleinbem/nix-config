{ inputs, config, ... }:
{
  # Overlays
  nixpkgs.overlays = [
    inputs.nur.overlays.default
    inputs.nix-packages.overlays.default
    inputs.antigravity-nix.overlays.default
    (_self: super: {
      stable = import inputs.nixpkgs-stable {
        inherit (super.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
    })
  ];

  imports = [
    ./options.nix
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
      userServices = true;
    };
    openFirewall = true;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs;
      inherit (inputs) nixpak;
      inherit (config) my;
    };
    backupFileExtension = "backup";
  };
}
