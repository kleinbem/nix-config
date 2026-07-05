{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;
  myInventory = import ../../inventory.nix;

  # Helper to create a nixosSystem for any host
  mkHost =
    name:
    {
      system ? myInventory.hosts.${name}.system,
      modules,
      extraSpecialArgs ? { },
    }:
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs self myInventory;
      }
      // extraSpecialArgs;
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

  # ── Deployment-driven factory enables (ADR 002) ──────────────────────────
  # The factories build exactly the union of containers registered with
  # my.services.container-updater on real hosts of the matching arch, plus an
  # explicit pre-warm list. Scanning is limited to this fixed host list —
  # never the factories themselves (that would recurse into their own config).
  deploySources = [
    "nixos-nvme"
    "core-pi"
    "hass-pi"
    "orin-nano"
    "nasbook"
  ];
  deployedContainers =
    system: extras:
    lib.unique (
      extras
      ++ lib.concatMap (
        name:
        let
          host = self.nixosConfigurations.${name};
        in
        if host.pkgs.stdenv.hostPlatform.system == system then
          host.config.my.services.container-updater.containers or [ ]
        else
          [ ]
      ) deploySources
    );

  # Containers to keep cached per arch beyond what's deployed — the escape
  # hatch for "I want to try X on some host this weekend" pre-warming.
  preWarm = {
    x86_64-linux = [ ];
    aarch64-linux = [ ];
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

      # --- Dedicated factories for building deployed standalone containers ---
      container-factory = mkHost "nixos-nvme" {
        system = "x86_64-linux";
        modules = [ ../../hosts/container-factory/default.nix ];
        extraSpecialArgs.deployedContainers = deployedContainers "x86_64-linux" preWarm.x86_64-linux;
      };
      # aarch64 twin: same catalogue minus x86-only heavies (see arm.nix), so
      # edge hosts (core-pi, hass-pi) run standalone containers from the same
      # CI-published manifest as the workstation.
      container-factory-aarch64 = mkHost "nixos-nvme" {
        system = "aarch64-linux";
        modules = [ ../../hosts/container-factory/arm.nix ];
        extraSpecialArgs.deployedContainers = deployedContainers "aarch64-linux" preWarm.aarch64-linux;
      };
    };

    diskoConfigurations = {
      inherit (self.nixosConfigurations.nixos-nvme.config) disko;
    };
  };
}
