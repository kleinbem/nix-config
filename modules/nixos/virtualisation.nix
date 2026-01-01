{ pkgs, ... }:

{
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
      # rootless = {
      #   enable = true;
      #   setSocketVariable = true;
      # };
    };

    # Podman (Side-by-side)
    podman = {
      enable = true;
      dockerCompat = false; # Do NOT alias docker to podman
      dockerSocket.enable = false; # Do NOT hijack /run/docker.sock
      defaultNetwork.settings.dns_enabled = true;
    };
    containers.enable = true;
  };

  # ==========================================
  # PODMAN SOCKETS (Rootful & Rootless)
  # ==========================================

  # ==========================================
  # PODMAN SOCKETS (Rootful & Rootless)
  # ==========================================

  systemd = {
    # Rootless Socket (User) - Enables automatic activation for 'martin'
    user.sockets.podman = {
      description = "Podman API Socket (rootless)";
      wantedBy = [ "sockets.target" ];
      unitConfig.ConditionUser = "martin";
      socketConfig = {
        ListenStream = "%t/podman/podman.sock"; # %t = $XDG_RUNTIME_DIR
        SocketMode = "0600";
      };
    };

    # Rootless Service
    user.services.podman = {
      description = "Podman API Service (rootless)";
      unitConfig.ConditionUser = "martin";
      requires = [ "podman.socket" ];
      after = [ "podman.socket" ];
      serviceConfig = {
        Type = "exec";
        KillMode = "process";
        Delegate = true;
        ExecStart = "${pkgs.podman}/bin/podman system service --time=0";
      };
    };
  };

  # Virtualization Tools
  environment.systemPackages = with pkgs; [
    podman
    podman-tui
    podman-compose
    docker-compose
  ];
}
