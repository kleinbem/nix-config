{ inputs, self, ... }:
let
  myInventory = import ../../inventory.nix;
  hostMeta = myInventory.hosts;
in
{
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
      imports = [ ../../hosts/nixos-nvme/default.nix ];
      nixpkgs.hostPlatform = hostMeta.nixos-nvme.system;
    };

    # OpenWrt routers (NixOS in LXC)
    router-1 = {
      deployment = {
        targetHost = hostMeta.router-1.ip;
        targetUser = "root";
        buildOnTarget = false;
        inherit (hostMeta.router-1) tags;
      };
      imports = [ ../../hosts/router-1/default.nix ];
      nixpkgs.hostPlatform = hostMeta.router-1.system;
      nixpkgs.buildPlatform = "x86_64-linux";
    };
    router-2 = {
      deployment = {
        targetHost = hostMeta.router-2.ip;
        targetUser = "root";
        buildOnTarget = false;
        inherit (hostMeta.router-2) tags;
      };
      imports = [ ../../hosts/router-2/default.nix ];
      nixpkgs.hostPlatform = hostMeta.router-2.system;
      nixpkgs.buildPlatform = "x86_64-linux";
    };

    # NVIDIA Jetson Orin Nano
    orin-nano = {
      deployment = {
        targetHost = hostMeta.orin-nano.ip;
        targetUser = "martin";
        buildOnTarget = true; # l4t kernel modules can't cross-compile from x86_64
        inherit (hostMeta.orin-nano) tags;
      };
      imports = [ ../../hosts/orin-nano/default.nix ];
      nixpkgs.hostPlatform = hostMeta.orin-nano.system;
    };

    # Raspberry Pi 5 nodes
    core-pi = {
      deployment = {
        targetHost = hostMeta.core-pi.ip;
        targetUser = "martin";
        buildOnTarget = false; # Temporarily false to push prebuilt kernel from workstation
        inherit (hostMeta.core-pi) tags;
      };
      imports = [ ../../hosts/core-pi/default.nix ];
      nixpkgs.hostPlatform = hostMeta.core-pi.system;
      nixpkgs.buildPlatform = "x86_64-linux";
    };
    hass-pi = {
      deployment = {
        targetHost = hostMeta.hass-pi.ip;
        targetUser = "martin";
        buildOnTarget = true;
        inherit (hostMeta.hass-pi) tags;
      };
      imports = [ ../../hosts/hass-pi/default.nix ];
      nixpkgs.hostPlatform = hostMeta.hass-pi.system;
    };
    nasbook = {
      deployment = {
        targetHost = hostMeta.nasbook.ip;
        targetUser = "root";
        inherit (hostMeta.nasbook) tags;
      };
      imports = [ ../../hosts/nasbook/default.nix ];
      nixpkgs.hostPlatform = hostMeta.nasbook.system;
    };
  };
}
