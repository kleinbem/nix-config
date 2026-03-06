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
    enable = lib.mkEnableOption "Virtualisation (Docker, Podman, Libvirt)";
  };

  config = lib.mkIf cfg.enable {
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
      };

      # Podman (Side-by-side)
      podman = {
        enable = true;
        dockerCompat = false;
        # Docker socket handled by actual Docker daemon (docker.enable = true)
        dockerSocket.enable = false;
        defaultNetwork.settings.dns_enabled = true;
      };

      # Raw LXC (Daemonless)
      lxc = {
        enable = true;
        lxcfs.enable = true;
        defaultConfig = "lxc.include = ${pkgs.lxc}/share/lxc/config/common.conf.d/00-lxcfs.conf";
      };
    };

    # HOTFIX: The virt-secret-init-encryption service uses /usr/bin/sh
    # We must clear the existing ExecStart list (using [""]) then add our fix.
    systemd.services.virt-secret-init-encryption = {
      serviceConfig.ExecStart = [
        ""
        "${pkgs.bash}/bin/sh -c 'umask 0077 && (${pkgs.coreutils}/bin/dd if=/dev/random status=none bs=32 count=1 | ${config.systemd.package}/bin/systemd-creds encrypt --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key)'"
      ];
    };

    # Delay GPU-enabled containers to ensure /dev/dri is ready at boot
    systemd.services."container@ollama".serviceConfig.ExecStartPre =
      [ "${pkgs.coreutils}/bin/sleep 5" ];

    # Native Bridge for NixOS Containers (Replaces Incusd's bridge)
    networking = {
      networkmanager.unmanaged = [ config.my.network.bridge ];
      # We still keep the NAT and basic interface config for firewall/routing
      interfaces."${config.my.network.bridge}".ipv4.addresses = [
        {
          address = config.my.network.hostAddress;
          prefixLength = 24;
        }
      ];
      nat = {
        enable = true;
        internalInterfaces = [ config.my.network.bridge ];
        externalInterface = "wlo1";
      };
    };

    # Force bridge creation via systemd (more reliable with NetworkManager)
    systemd.services."create-${config.my.network.bridge}-bridge" = {
      description = "Create ${config.my.network.bridge} bridge for containers";
      after = [ "network-pre.target" ];
      before = [
        "network.target"
        "container@n8n.service"
        "container@ollama.service"
        "container@code-server.service"
        "container@silverbullet.service"
        "container@open-webui.service"
        "container@dashboard.service"
        "container@qdrant.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.iproute2}/bin/ip link add name ${config.my.network.bridge} type bridge || true
        ${pkgs.iproute2}/bin/ip link set ${config.my.network.bridge} up || true
        # IP address is handled by networking.interfaces
      '';
    };

    # ==========================================
    # PODMAN SOCKETS (Rootful & Rootless)
    # ==========================================

    systemd = {
      # Ensure /images is owned by the user and libvirtd group
      tmpfiles.rules = [
        "z /images 0775 ${config.my.username} libvirtd - -"
      ];
    };

    programs.virt-manager.enable = true;

    # Virtualization Tools
    environment.systemPackages = with pkgs; [
      virt-manager

      podman-tui
      podman-compose
      docker-compose
      crosvm
    ];
  };
}
