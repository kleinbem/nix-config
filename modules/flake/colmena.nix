{ inputs, self, ... }:
let
  myInventory = import ../../inventory.nix;
  hostMeta = myInventory.hosts;
in
{
  # Direct flake evaluation (colmena >= 0.5.0-pre). The old getFlake evaluator
  # broke Attic substitution with mismatched version labels (colmena#162).
  flake.colmenaHive = inputs.colmena.lib.makeHive self.colmena;

  flake.colmena = {
    meta = {
      nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      specialArgs = {
        inherit inputs self myInventory;
        secretFile = import ../../lib/secret-file.nix { inherit inputs; };
      };
    };

    # Main workstation (deploy locally)
    nixos-nvme = {
      deployment = {
        allowLocalDeployment = true;
        targetHost = null; # Local deployment
      };
      imports = [
        ../../hosts/nixos-nvme/default.nix
        ../nixos/colmena-version-metadata.nix
      ];
      nixpkgs.hostPlatform = hostMeta.nixos-nvme.system;
    };

    # NVIDIA Jetson Orin Nano
    orin-nano = {
      deployment = {
        targetHost = hostMeta.orin-nano.ip;
        targetUser = "martin";
        buildOnTarget = true; # Build natively on the Orin Nano itself to avoid slow QEMU cross-compilation on the workstation
        inherit (hostMeta.orin-nano) tags;
      };
      imports = [
        ../../hosts/orin-nano/default.nix
        ../nixos/colmena-version-metadata.nix
      ];
      nixpkgs.hostPlatform = hostMeta.orin-nano.system;
    };

    # Raspberry Pi 5 nodes
    core-pi = {
      deployment = {
        targetHost = hostMeta.core-pi.ip;
        targetUser = "martin";
        buildOnTarget = false; # Evaluates on workstation, fetches from Attic, pushes via SSH
        inherit (hostMeta.core-pi) tags;
      };
      imports = [
        ../../hosts/core-pi/default.nix
        ../nixos/colmena-version-metadata.nix
      ];
      nixpkgs.hostPlatform = hostMeta.core-pi.system;
    };
    hass-pi = {
      deployment = {
        targetHost = hostMeta.hass-pi.ip;
        targetUser = "martin";
        buildOnTarget = false;
        inherit (hostMeta.hass-pi) tags;
      };
      imports = [
        ../../hosts/hass-pi/default.nix
        ../nixos/colmena-version-metadata.nix
      ];
      nixpkgs.hostPlatform = hostMeta.hass-pi.system;
    };
    nasbook = {
      deployment = {
        targetHost = hostMeta.nasbook.ip;
        targetUser = "martin";
        inherit (hostMeta.nasbook) tags;
      };
      imports = [
        ../../hosts/nasbook/default.nix
        ../nixos/colmena-version-metadata.nix
      ];
      nixpkgs.hostPlatform = hostMeta.nasbook.system;
    };

    mac-mini = {
      deployment = {
        targetHost = hostMeta.mac-mini.ip;
        targetUser = "martin";
        buildOnTarget = false; # same x86_64 arch as nixos-nvme — fast native build, push via SSH
        inherit (hostMeta.mac-mini) tags;
      };
      imports = [
        ../../hosts/mac-mini/default.nix
        ../nixos/colmena-version-metadata.nix
      ];
      nixpkgs.hostPlatform = hostMeta.mac-mini.system;
    };
  };
}
