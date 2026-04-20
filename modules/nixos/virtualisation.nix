{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.my.virtualisation;
  inv = import ../../inventory.nix;
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
        autoPrune = {
          enable = true;
          dates = "daily";
        };
      };

      # Podman (Side-by-side)
      podman = {
        enable = true;
        dockerCompat = false;
        # Docker socket handled by actual Docker daemon (docker.enable = true)
        dockerSocket.enable = false;
        defaultNetwork.settings.dns_enabled = true;
        autoPrune = {
          enable = true;
          dates = "daily";
          flags = [ "--all" ];
        };
      };

      # Redirect Podman storage to disk (Prevent /var tmpfs exhaustion)
      containers = {
        enable = true;
        storage.settings = {
          storage = {
            driver = "overlay";
            graphroot = "/var/lib/images/podman";
            runroot = "/run/containers/storage";
          };
        };
      };

      # Raw LXC (Daemonless)
      lxc = {
        enable = true;
        lxcfs.enable = true;
        defaultConfig = "lxc.include = ${pkgs.lxc}/share/lxc/config/common.conf.d/00-lxcfs.conf";
      };
    };

    # Native Bridge for NixOS Containers (Replaces Incusd's bridge)
    networking = {
      bridges."${config.my.network.bridge}".interfaces = [ ];
      networkmanager.unmanaged = [ config.my.network.bridge ];
      # We still keep the NAT and basic interface config for firewall/routing
      # We don't assign the IP here; podman-network-cbr0.service will handle it
      # to avoid "subnet already exists" conflicts during Podman activation.
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

      # Egress Airlock and Zero-Trust rules moved to zero-trust.nix for centralization
    };

    # ==========================================
    # PODMAN SOCKETS (Rootful & Rootless)
    # ==========================================

    systemd = {
      # Ensure /images is owned by the user and libvirtd group
      tmpfiles.rules = [
        "d /images 0775 ${config.my.username} libvirtd - -"
        "d /var/lib/images/podman 0755 root root - -"
        "d /var/lib/images/podman/tmp 1777 root root - -"
      ];

      # Consolidated services
      services = {
        # HOTFIX: The virt-secret-init-encryption service uses /usr/bin/sh
        virt-secret-init-encryption = {
          serviceConfig.ExecStart = [
            ""
            "${pkgs.bash}/bin/sh -c 'umask 0077 && (${pkgs.coreutils}/bin/dd if=/dev/random status=none bs=32 count=1 | ${config.systemd.package}/bin/systemd-creds encrypt --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key)'"
          ];
        };

        # Ensure the Podman network exists and provides the physical bridge for ALL containers
        podman-network-cbr0 = {
          description = "Ensure Podman cbr0 network exists";
          after = [
            "podman.service"
            "network-pre.target"
          ];
          before = [
            "podman-vllm.service"
            "podman-litellm.service"
            "podman-comfyui.service"
            "podman-langflow.service"
            "podman-langfuse.service"
            "podman-langfuse-db.service"
          ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            # 1. Clear any dangling podman network to avoid "subnet already exists"
            ${pkgs.podman}/bin/podman network rm -f cbr0 || true

            # 2. Re-create the network with the EXISTING physical bridge.
            # We use mode=unmanaged to tell Podman we already handle the bridge.
            # We explicitly DISABLE DNS to avoid port 53 conflicts on the host gateway IP.
            ${pkgs.podman}/bin/podman network create \
              --driver bridge \
              --interface-name ${config.my.network.bridge} \
              --subnet ${inv.network.subnet} \
              --gateway ${config.my.network.hostAddress} \
              --disable-dns \
              --opt mode=unmanaged \
              --opt "com.docker.network.bridge.name=${config.my.network.bridge}" \
              cbr0

            # 3. Force the interface UP (redundant but safe)
            ${pkgs.iproute2}/bin/ip link set ${config.my.network.bridge} up || true
          '';
        };
      }
      //
        lib.genAttrs
          [
            "container@n8n"
            "container@code-server"
            "container@open-webui"
            "container@dashboard"
            "container@qdrant"
          ]
          (_name: {
            after = [
              "podman-network-cbr0.service"
            ];
            requires = [
              "podman-network-cbr0.service"
            ];
          });
    };

    programs.virt-manager.enable = true;

    environment.systemPackages = with pkgs; [
      virt-manager
      podman-tui
      podman-compose
      docker-compose
      crosvm
    ];
  };
}
