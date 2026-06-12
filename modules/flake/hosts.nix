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
                # nixpkgs github-runner 2.334.0 still bundles Node 20 internally;
                # remove once nixpkgs upgrades it to Node 22.
                "nodejs-20.20.2"
                "nodejs-slim-20.20.2"
                "openclaw-2026.5.12"
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
      core-pi-cross = mkHost "core-pi" {
        modules = [
          ../../hosts/core-pi/default.nix
          { nixpkgs.buildPlatform = "x86_64-linux"; }
        ];
      };
      hass-pi = mkHost "hass-pi" {
        modules = [ ../../hosts/hass-pi/default.nix ];
      };
      hass-pi-cross = mkHost "hass-pi" {
        modules = [
          ../../hosts/hass-pi/default.nix
          { nixpkgs.buildPlatform = "x86_64-linux"; }
        ];
      };
      nasbook = mkHost "nasbook" {
        modules = [ ../../hosts/nasbook/default.nix ];
      };

      # --- Dedicated factory for building ALL standalone containers ---
      container-factory = mkHost "nixos-nvme" {
        system = "x86_64-linux";
        modules = [ ../../hosts/container-factory/default.nix ];
      };
    };

    diskoConfigurations = {
      inherit (self.nixosConfigurations.nixos-nvme.config) disko;
    };
  };
}
