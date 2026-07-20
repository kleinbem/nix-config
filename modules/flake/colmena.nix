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

    # NVIDIA Jetson Orin Nano
    orin-nano = {
      deployment = {
        targetHost = hostMeta.orin-nano.ip;
        targetUser = "martin";
        buildOnTarget = false; # Evaluates on workstation, fetches from Attic, pushes via SSH
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
        buildOnTarget = false; # Evaluates on workstation, fetches from Attic, pushes via SSH
        inherit (hostMeta.core-pi) tags;
      };
      imports = [ ../../hosts/core-pi/default.nix ];
      nixpkgs.hostPlatform = hostMeta.core-pi.system;
    };
    hass-pi = {
      deployment = {
        targetHost = hostMeta.hass-pi.ip;
        targetUser = "martin";
        buildOnTarget = false;
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
