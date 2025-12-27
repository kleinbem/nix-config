{ pkgs, ... }:

{
  # ==========================================
  # VIRTUALIZATION
  # ==========================================
  virtualisation = {
    libvirtd = {
      enable = true;
      onBoot = "ignore";
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
    # Rootful Socket (System)
    sockets.podman = {
      description = "Podman API Socket (rootful)";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "/run/podman/podman.sock";
        SocketMode = "0660";
        SocketUser = "root";
        SocketGroup = "podman";
      };
    };

    # Rootful Service
    services.podman = {
      description = "Podman API Service (rootful)";
      requires = [ "podman.socket" ];
      after = [ "podman.socket" ];
      serviceConfig = {
        Type = "exec";
        KillMode = "process";
        Delegate = true;
        ExecStart = "${pkgs.podman}/bin/podman system service --time=0";
      };
    };

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
