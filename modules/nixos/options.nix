{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  myInventory = import ../../inventory.nix;
in
{
  options.my = {
    username = mkOption {
      type = types.str;
      default = myInventory.user or "martin";
      description = "The primary system username.";
    };

    home = mkOption {
      type = types.path;
      default = "/home/${config.my.username}";
      description = "The primary user's home directory path.";
    };

    developDir = mkOption {
      type = types.path;
      default = "${config.my.home}/Develop/github.com/kleinbem";
      description = "The primary development root directory.";
    };

    git = {
      name = mkOption {
        type = types.str;
        default = myInventory.git.name or "kleinbem";
        description = "Primary Git username.";
      };
      email = mkOption {
        type = types.str;
        default = myInventory.git.email or "martin.kleinberger@gmail.com";
        description = "Primary Git email. Real value lives in inventory.nix; fallback is the gmail address — switching to a kleinbem.dev address must wait until Phase 1 (Stalwart) and GitHub-account email verification.";
      };
    };

    network = {
      subnet = mkOption {
        type = types.str;
        default = myInventory.network.subnet or "10.85.46.0/24";
        description = "The container network subnet.";
      };
      bridge = mkOption {
        type = types.str;
        default = myInventory.network.bridge or "cbr0";
        description = "The container bridge interface name.";
      };
      hostAddress = mkOption {
        type = types.str;
        default = myInventory.hosts.nixos-nvme.ip;
        description = "The host address on the container bridge.";
      };
      externalInterface = mkOption {
        type = types.str;
        default = "wlo1";
        description = "The external/WAN interface name.";
      };
    };

    hardware = {
      gpuRenderNode = mkOption {
        type = types.str;
        default = myInventory.hardware.gpuRenderNode or "/dev/dri/renderD128";
        description = "The GPU render node path.";
      };
    };

    services = mkOption {
      type = types.submoduleWith {
        modules = [ ];
        shorthandOnlyDefinesConfig = true;
      };
      default = { };
      description = "Custom services defined under the 'my' namespace.";
    };

    containers = mkOption {
      type = types.submoduleWith {
        modules = [ ];
        shorthandOnlyDefinesConfig = true;
      };
      default = { };
      description = "Custom container definitions under the 'my' namespace.";
    };

    monitoring = mkOption {
      type = types.submoduleWith {
        modules = [ ];
        shorthandOnlyDefinesConfig = true;
      };
      default = { };
      description = "Custom monitoring settings under the 'my' namespace.";
    };
  };

  # Compatibility shim for nix-mineral vs newer nixpkgs
  options.systemd.coredump.settings = mkOption {
    type = types.submodule {
      freeformType = types.attrsOf types.anything;
    };
    default = { };
    description = "Shim for nix-mineral which expects this option to exist.";
  };
}
