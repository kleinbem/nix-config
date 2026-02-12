{ config, lib, ... }:

let
  cfg = config.my.services.redroid;
in
{
  options.my.services.redroid = {
    enable = lib.mkEnableOption "Redroid (Remote Android) Container";

    image = lib.mkOption {
      type = lib.types.str;
      default = "redroid/redroid:16.0.0-latest";
      description = "The Docker image to use for Redroid. Use a custom image tag if you need GApps.";
    };

    gpu = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable GPU acceleration for the container.";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 5555;
      description = "Port to expose for ADB connection.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Redroid requires specific kernel modules and configuration
    boot.kernelModules = [
      "binder_linux"
      "ashmem_linux"
    ];
    boot.extraModprobeConfig = ''
      options binder_linux devices="binder,hwbinder,vndbinder"
    '';

    virtualisation.oci-containers.containers.redroid = {
      inherit (cfg) image;
      ports = [ "${toString cfg.port}:5555" ];
      extraOptions = [
        "--privileged"
        "--device=/dev/binder:/dev/binder"
        "--device=/dev/hwbinder:/dev/hwbinder"
        "--device=/dev/vndbinder:/dev/vndbinder"
      ]
      ++ lib.optionals cfg.gpu [
        "--device=/dev/dri:/dev/dri" # Intel/AMD/Pi 5 GPU mapping
      ];
    };

    # Start udev rules for Zotac Intel GPU and Pi 5 Broadcom GPU permissions
    services.udev.extraRules = ''
      KERNEL=="binder", MODE="0666", GROUP="docker"
      KERNEL=="hwbinder", MODE="0666", GROUP="docker"
      KERNEL=="vndbinder", MODE="0666", GROUP="docker"
    '';
  };
}
