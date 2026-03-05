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
        description = "Primary Git email.";
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
        default = "10.85.46.1"; # Often derived from subnet but fixed here for simplicity
        description = "The host address on the container bridge.";
      };
    };

    hardware = {
      gpuRenderNode = mkOption {
        type = types.str;
        default = myInventory.hardware.gpuRenderNode or "/dev/dri/renderD128";
        description = "The GPU render node path.";
      };
    };
  };
}
