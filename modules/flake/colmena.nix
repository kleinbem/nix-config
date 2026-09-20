{ inputs, self, ... }:
let
  myInventory = import ../../inventory.nix;
  hostMeta = myInventory.hosts;
in
{
  # Direct flake evaluation (colmena >=0.5.0-pre, github:nix-community/colmena
  # main). Purely additive — wraps the existing `flake.colmena` output below,
  # no restructuring needed. This is what actually fixes nix-community/
  # colmena#162 (mismatched version labels breaking Attic substitution — see
  # its own comment thread) and the separate "/tmp/colmena-assets-*"
  # bootstrap breakage we hit trying to patch around #162 from userland: both
  # were artifacts of the OLD builtins.getFlake + temp-copy evaluator, which
  # this bypasses entirely.
  flake.colmenaHive = inputs.colmena.lib.makeHive self.colmena;

  flake.colmena = {
    meta = {
      nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      specialArgs = {
        inherit inputs self myInventory;
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
        # Static IP migration complete (hosts/mac-mini/default.nix stage 2) —
        # .16 is now the host's real, sole address; DHCP's .70 is retired.
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
