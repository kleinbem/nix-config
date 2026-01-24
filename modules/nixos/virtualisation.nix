{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.my.virtualisation;
in
{
  options.my.virtualisation = {
    enable = lib.mkEnableOption "Virtualisation (Incus, Docker, Podman, Libvirt)";
  };

  config = lib.mkIf cfg.enable {
    # ==========================================
    # VIRTUALIZATION
    # ==========================================
    virtualisation = {
      libvirtd = {
        enable = true;
        onBoot = "ignore";
        # Disable auto-starting the service itself if possible, though 'enable = true' usually implies wantedBy multi-user.
        # NixOS libvirtd module doesn't perfectly support "installed but disabled",
        # but onBoot="ignore" stops VMs.
      };

      # Docker (Primary for DevContainers/Compatibility)
      docker = {
        enable = true;
      };

      # Podman (Side-by-side)
      # Note: We do NOT alias docker to podman (dockerCompat=false) to allow them to co-exist.
      # Docker handles DevContainers/NVIDIA, while Podman handles System Containers/RHEL workflows.
      podman = {
        enable = true;
        dockerCompat = false;
        dockerSocket.enable = false; # Do NOT hijack /run/docker.sock
        defaultNetwork.settings.dns_enabled = true;
      };

      # Incus (System Containers)
      incus = {
        enable = true;
        package = pkgs.incus;
        ui.enable = true;
      };
    };

    # ==========================================
    # PODMAN SOCKETS (Rootful & Rootless)
    # ==========================================

    # ==========================================
    # PODMAN SOCKETS (Rootful & Rootless)
    # ==========================================

    systemd = {
      # Ensure /images is owned by the user and libvirtd group
      tmpfiles.rules = [
        "z /images 0775 martin libvirtd - -"
      ];
    };

    programs.virt-manager.enable = true;

    # Virtualization Tools
    environment.systemPackages = with pkgs; [
      virt-manager

      podman
      podman-tui
      podman-compose
      docker-compose
    ];
  };
}
