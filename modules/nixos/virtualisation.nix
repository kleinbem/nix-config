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
      };

      # Podman (Side-by-side)
      podman = {
        enable = true;
        dockerCompat = false;
        # Docker socket handled by actual Docker daemon (docker.enable = true)
        dockerSocket.enable = false;
        defaultNetwork.settings.dns_enabled = true;
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

      # Zero Trust: Replicate mkContainer firewall on the host for Podman IPs
      nftables.tables.zt-podman = {
        family = "inet";
        content = ''
          chain forward {
            type filter hook forward priority 0; policy accept;
            
            # 1. Allow established/related
            ct state { established, related } accept
            
            # 2. Allow AI Stack to talk to host bridge (for DNS/Services)
            ip saddr { 
              ${inv.network.nodes.vllm.ip}, 
              ${inv.network.nodes.litellm.ip}, 
              ${inv.network.nodes.comfyui.ip}, 
              ${inv.network.nodes.langflow.ip}, 
              ${inv.network.nodes.langfuse.ip} 
            } ip daddr ${config.my.network.hostAddress} accept
            
            # 3. Allow internal flows
            # LiteLLM -> vLLM (Main Backend)
            ip saddr ${inv.network.nodes.litellm.ip} ip daddr ${inv.network.nodes.vllm.ip} tcp dport 8000 accept
            
            # Allow East-West within the bridge for these specific AI IPs
            ip saddr {
              ${inv.network.nodes.vllm.ip},
              ${inv.network.nodes.litellm.ip},
              ${inv.network.nodes.comfyui.ip},
              ${inv.network.nodes.langflow.ip},
              ${inv.network.nodes.langfuse.ip}
            } ip daddr ${inv.network.subnet} accept

            # 4. Mandatory Egress Airlock (Allow DNS & HTTPS for Model Pulls)
            ip saddr {
              ${inv.network.nodes.vllm.ip},
              ${inv.network.nodes.litellm.ip},
              ${inv.network.nodes.comfyui.ip},
              ${inv.network.nodes.langflow.ip},
              ${inv.network.nodes.langfuse.ip}
            } udp dport 53 accept
            ip saddr {
              ${inv.network.nodes.vllm.ip},
              ${inv.network.nodes.litellm.ip},
              ${inv.network.nodes.comfyui.ip},
              ${inv.network.nodes.langflow.ip},
              ${inv.network.nodes.langfuse.ip}
            } tcp dport { 53, 443 } accept

            # 5. Final Zero-Trust Egress Deny
            ip saddr {
              ${inv.network.nodes.vllm.ip},
              ${inv.network.nodes.litellm.ip},
              ${inv.network.nodes.comfyui.ip},
              ${inv.network.nodes.langflow.ip},
              ${inv.network.nodes.langfuse.ip}
            } log prefix "ZT-PODMAN-EGRESS-DENY: " drop
          }
        '';
      };
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
            # We explicitly DISABLE DNS to avoid port 53 conflicts on the host gateway IP.
            ${pkgs.podman}/bin/podman network create \
              --driver bridge \
              --interface-name ${config.my.network.bridge} \
              --subnet ${inv.network.subnet} \
              --gateway ${config.my.network.hostAddress} \
              --disable-dns \
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
              "bridge-${config.my.network.bridge}.service"
            ];
            requires = [
              "podman-network-cbr0.service"
              "bridge-${config.my.network.bridge}.service"
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
