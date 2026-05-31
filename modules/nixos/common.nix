{
  inputs,
  config,
  myInventory,
  ...
}:
{
  # Overlays
  nixpkgs.overlays = [
    inputs.nur.overlays.default
    inputs.nix-packages.overlays.default
    inputs.nix-vscode-extensions.overlays.default
    inputs.nix-topology.overlays.default
    (_final: prev: {
      stable = import inputs.nixpkgs-stable {
        inherit (prev.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };

      master = import inputs.nixpkgs-master {
        inherit (prev.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
    })

  ];

  imports = [
    ./options.nix
    ./hardening.nix
    ./snapper.nix
    ./network-routing.nix
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  environment.etc."specialisation".text = "base";

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    reflector = true; # Allow mDNS discovery across the container bridge
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
      inherit inputs myInventory;
      inherit (config) my;
    };
    backupFileExtension = "backup";
  };
}
