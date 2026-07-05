{ inputs, self, ... }:
let
  myInventory = import ../../inventory.nix;

  # Helper to create a nixosSystem for any host
  mkHost =
    name:
    {
      system ? myInventory.hosts.${name}.system,
      modules,
    }:
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs self myInventory;
      };
      modules = [
        inputs.nix-flatpak.nixosModules.nix-flatpak
        {
          nixpkgs = {
            hostPlatform = system;
            config = {
              allowUnfree = true;
              allowUnfreePredicate = _: true;
              android_sdk.accept_license = true;
              permittedInsecurePackages = [
                "openclaw-2026.6.5"
              ];
            };
          };
        }
      ]
      ++ (if builtins.isList modules then modules else [ modules ]);
    };
in
{
  flake = {
    nixosConfigurations = {
      nixos-nvme = mkHost "nixos-nvme" {
        modules = [ ../../hosts/nixos-nvme/default.nix ];
      };
      router-1 = mkHost "router-1" {
        modules = [ ../../hosts/router-1/default.nix ];
      };
      router-2 = mkHost "router-2" {
        modules = [ ../../hosts/router-2/default.nix ];
      };
      orin-nano = mkHost "orin-nano" {
        modules = [ ../../hosts/orin-nano/default.nix ];
      };
      orin-nano-bootstrap = mkHost "orin-nano-bootstrap" {
        system = "aarch64-linux";
        modules = [ ../../hosts/orin-nano-bootstrap/default.nix ];
      };
      core-pi = mkHost "core-pi" {
        modules = [ ../../hosts/core-pi/default.nix ];
      };
      hass-pi = mkHost "hass-pi" {
        modules = [ ../../hosts/hass-pi/default.nix ];
      };
      nasbook = mkHost "nasbook" {
        modules = [ ../../hosts/nasbook/default.nix ];
      };

      # --- Dedicated factory for building ALL standalone containers ---
      container-factory = mkHost "nixos-nvme" {
        system = "x86_64-linux";
        modules = [ ../../hosts/container-factory/default.nix ];
      };
      # aarch64 twin: same container set minus x86-only heavies (see arm.nix),
      # so edge hosts (core-pi, hass-pi) can run standalone containers from the
      # same CI-published manifest as the workstation.
      container-factory-aarch64 = mkHost "nixos-nvme" {
        system = "aarch64-linux";
        modules = [ ../../hosts/container-factory/arm.nix ];
      };
    };

    diskoConfigurations = {
      inherit (self.nixosConfigurations.nixos-nvme.config) disko;
    };
  };
}
