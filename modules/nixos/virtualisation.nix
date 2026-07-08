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

    libvirtd.enable = lib.mkOption {
      type = lib.types.bool;
      # Default `false` so headless hosts don't pull in virt-manager (the only
      # GUI app in the headless tier). Workstations that actually use KVM
      # opt in explicitly.
      default = false;
      description = "Enable host-level libvirtd daemon and tools (incl. virt-manager GUI).";
    };

    podman.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable host-level Podman container engine and tools.";
    };

    lxc.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable host-level LXC daemonless tools.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # ==========================================
    # VIRTUALIZATION
    # ==========================================
    virtualisation = {
      libvirtd = {
        inherit (cfg.libvirtd) enable;
        onBoot = "start";
      };

      # Docker (Disabled in favor of Podman)
      docker.enable = false;

      # Podman (Side-by-side)
      podman = {
        inherit (cfg.podman) enable;
        # Provide Docker-compatible socket via Podman
        dockerSocket.enable = cfg.podman.enable;
        dockerCompat = cfg.podman.enable;
        defaultNetwork.settings.dns_enabled = true;
        autoPrune = {
          inherit (cfg.podman) enable;
          dates = "daily";
          flags = [ "--all" ];
        };
      };

      # Redirect Podman storage to disk (Prevent /var tmpfs exhaustion)
      containers = lib.mkIf cfg.podman.enable {
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
        inherit (cfg.lxc) enable;
        lxcfs.enable = cfg.lxc.enable;
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
        internalInterfaces = [
          config.my.network.bridge
        ]
        ++ lib.optional cfg.libvirtd.enable "virbr0";
        inherit (config.my.network) externalInterface;
      };

      # Egress Airlock and Zero-Trust rules moved to zero-trust.nix for centralization
      firewall = {
        trustedInterfaces = lib.optional cfg.libvirtd.enable "virbr0";
        extraForwardRules = ''
          # Container Bridge
          iifname "${config.my.network.bridge}" oifname "${config.my.network.externalInterface}" accept
          iifname "${config.my.network.externalInterface}" oifname "${config.my.network.bridge}" ct state { established, related } accept
          iifname "${config.my.network.externalInterface}" oifname "${config.my.network.bridge}" ip saddr { 10.0.0.5, 10.0.0.22, 10.0.0.12, 10.0.0.21, 10.0.0.30, 10.0.0.1, 10.0.0.2, 10.0.0.3, 10.0.0.4, 10.0.0.7, 10.0.0.6 } accept
        ''
        + lib.optionalString cfg.libvirtd.enable ''

          # Libvirt Bridge (Bluefin)
          iifname "virbr0" oifname "${config.my.network.externalInterface}" accept
          iifname "${config.my.network.externalInterface}" oifname "virbr0" ct state { established, related } accept
        '';
      };
    };

    # ==========================================
    # PODMAN SOCKETS (Rootful & Rootless)
    # ==========================================

    systemd = {
      # Ensure /images is owned by the user and libvirtd group
      tmpfiles.rules = lib.flatten [
        (lib.optional cfg.libvirtd.enable "d /images 0775 ${config.my.username} libvirtd - -")
        (lib.optionals cfg.podman.enable [
          "d /var/lib/images/podman 0755 root root - -"
          "d /var/lib/images/podman/tmp 1777 root root - -"
        ])
      ];

      # Consolidated services
      services = {
        # HOTFIX: The virt-secret-init-encryption service uses /usr/bin/sh
        virt-secret-init-encryption = lib.mkIf cfg.libvirtd.enable {
          serviceConfig.ExecStart = [
            ""
            "${pkgs.bash}/bin/sh -c 'umask 0077 && (${pkgs.coreutils}/bin/dd if=/dev/random status=none bs=32 count=1 | ${config.systemd.package}/bin/systemd-creds encrypt --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key)'"
          ];
        };

        # Ensure the Podman network exists and provides the physical bridge for ALL containers
        podman-network-cbr0 = lib.mkIf cfg.podman.enable {
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
            "container@n8n.service"
            "container@code-server.service"
            "container@open-webui.service"
            "container@dashboard.service"
            "container@qdrant.service"
          ];
          wantedBy = [
            "multi-user.target"
          ];
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
              --subnet ${config.my.network.subnet} \
              --gateway ${config.my.network.hostAddress} \
              --disable-dns \
              --opt mode=unmanaged \
              --opt "com.docker.network.bridge.name=${config.my.network.bridge}" \
              cbr0

            # 3. Force the interface UP (redundant but safe)
            ${pkgs.iproute2}/bin/ip link set ${config.my.network.bridge} up || true
          '';
        };

        # Ensure libvirt 'default' network is active
        libvirtd = lib.mkIf cfg.libvirtd.enable {
          postStart = ''
            ${pkgs.libvirt}/bin/virsh net-start default || true
          '';
        };
      };

    };

    programs.virt-manager.enable = cfg.libvirtd.enable;

    environment.systemPackages = lib.flatten [
      (lib.optionals cfg.libvirtd.enable [
        pkgs.virt-manager
        pkgs.libvirt
      ])
      (lib.optionals cfg.podman.enable [
        pkgs.podman-tui
        pkgs.podman-compose
        pkgs.docker-compose
      ])
      (lib.optional (cfg.libvirtd.enable || cfg.lxc.enable) pkgs.crosvm)
    ];
  };
}
