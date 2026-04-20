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
        hostPlatform = prev.stdenv.hostPlatform.system;
        config.allowUnfree = true;
      };
      master = import inputs.nixpkgs-master {
        hostPlatform = prev.stdenv.hostPlatform.system;
        config.allowUnfree = true;
      };
      # Fix netbird build failure by using stable version (Go 1.23 is removed from unstable)
      inherit (final.stable) netbird netbird-ui;

      # Suppress Electron "unknown option" warnings in Antigravity by using environment variables
      # instead of CLI flags for Wayland/Ozone support.
      antigravity-fhs = prev.antigravity-fhs.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeWrapper ];
        postFixup = (old.postFixup or "") + ''
          wrapProgram $out/bin/antigravity \
            --set ELECTRON_OZONE_PLATFORM_HINT auto \
            --set NIXOS_OZONE_WL 1 \
            --set ELECTRON_DISABLE_STDOUT_WARNINGS 1
        '';
      });
    })
  ];

  imports = [
    ./options.nix
    ./hardening.nix
    ./snapper.nix
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
