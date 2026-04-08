{ inputs, config, ... }:
{
  # Overlays
  nixpkgs.overlays = [
    inputs.nur.overlays.default
    inputs.nix-packages.overlays.default
    inputs.antigravity-nix.overlays.default
    inputs.nix-vscode-extensions.overlays.default
    inputs.nix-topology.overlays.default
    (final: prev: {
      stable = import inputs.nixpkgs-stable {
        inherit (prev.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
      master = import inputs.nixpkgs-master {
        inherit (prev.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
      # Fix netbird build failure by using stable version (Go 1.23 is removed from unstable)
      inherit (final.stable) netbird netbird-ui;
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
