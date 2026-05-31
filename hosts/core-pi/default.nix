# core-pi — Raspberry Pi 5
{
  inputs,
  self,
  myInventory,
  lib,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
in
{
  imports = [
    inputs.nix-hardware.nixosModules.rpi5
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"
    "${self}/modules/nixos/persistence.nix"
    "${self}/modules/nixos/virtualisation.nix"
    "${self}/modules/nixos/pki.nix"
    "${self}/modules/nixos/networking.nix"
    "${self}/modules/nixos/network-routing.nix"
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.monitoring-node
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.anythingllm
    inputs.nix-presets.nixosModules.ollama
    inputs.nix-presets.nixosModules.dashboard
    inputs.nix-presets.nixosModules.cups
  ];

  networking.hostName = "core-pi";

  my = {
    services.rpi-eeprom.enable = true;

    # Container bridge (cbr0), NAT, IP forwarding and firewall forward rules
    # for the nspawn containers below. Without this, container@dashboard /
    # container@cups can't attach to the non-existent bridge.
    virtualisation = {
      enable = true;
      libvirtd.enable = false;
      podman.enable = false;
      lxc.enable = false;
    };

    network = {
      subnet = "10.85.48.0/24";
      hostAddress = "10.85.48.1";
      externalInterface = "end0";
    };

    # ─── Frontend Services ──────────────────────────────────────
    containers = {
      open-webui = {
        enable = false;
        ip = "${myInventory.network.nodes.open-webui.ip}/24";
        hostDataDir = "/var/lib/open-webui";
        vllmUrl = "https://litellm.internal";
        memoryLimit = "1.5G";
      };

      # ─── AI Agents (Ready for deployment) ───────────────────────
      # These are hosted on the Pi to keep the Orin Nano slim.
      openclaw = {
        enable = false; # Set to true to enable
        ip = "${myInventory.network.nodes.openclaw.ip}/24";
        vllmUrl = "https://litellm.internal";
        hostDataDir = "/var/lib/openclaw";
      };

      agent-zero = {
        enable = false; # Set to true to enable
        ip = "${myInventory.network.nodes.agent-zero.ip}/24";
        hostDataDir = "/var/lib/agent-zero";
        vllmUrl = "https://litellm.internal";
      };

      # ─── Ollama (Offloaded to Orin Nano) ────────────────────────
      ollama.enable = false;

      anythingllm = {
        enable = false;
        ip = "${myInventory.network.nodes.anythingllm.ip}/24";
        hostDataDir = "/var/lib/anythingllm";
        llmUrl = "https://litellm.internal";
        modelName = "google/gemma-2b"; # Aligned with Orin Nano backend in ai.nix
        memoryLimit = "2G";
      };

      dashboard = {
        enable = true;
        ip = "10.85.48.103/24";
        hostBridgeIp = "10.0.0.20"; # core-pi IP
        memoryLimit = "512M";
      };

      cups = {
        enable = true;
        ip = "${myInventory.network.nodes.cups.ip}/24";
      };
    };
    monitoring.node.enable = true;
  };

  # ─── Networking & Security ──────────────────────────────────
  services = {
    netbird.enable = true;

    # SSD Health
    fstrim.enable = true;

    # systemd-resolved as local DNS resolver
    resolved = {
      enable = true;
      settings = {
        Resolve = {
          FallbackDNS = "1.1.1.1 8.8.8.8";
          DNSSEC = "false";
        };
      };
    };
  };

  networking = {
    useDHCP = false;
    # systemd-resolved manages DNS; disable resolvconf to avoid conflict with networking.nix
    resolvconf.enable = lib.mkForce false;
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    interfaces = {
      "end0" = {
        ipv4 = {
          addresses = [
            {
              address = "10.0.0.20";
              prefixLength = 16;
            }
          ];
          routes = lib.mkForce [ ];
        };
      };
    };
    defaultGateway = {
      address = "10.0.0.1";
      interface = "end0";
    };
    firewall = {
      enable = true;
      # Allow SSH on physical LAN interface (end0) and Netbird (wt0)
      interfaces = {
        "end0".allowedTCPPorts = [ 22 ];
        "wt0".allowedTCPPorts = [ 22 ];
      };
    };
  };

  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "10.0.0.12"; # Orin Nano via LAN
        sshUser = "martin";
        systems = [ "aarch64-linux" ];
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
      }
    ];
  };

  users.users.martin.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
    keys.ssh.fido2
    keys.ssh.fido2-backup
  ];

  # --- Stateless Root (Impermanence) ---
  fileSystems = {
    "/" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=2G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    "/var" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=2G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    "/nix" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      neededForBoot = true;
      options = [ "noatime" ];
    };
    "/boot" = {
      device = "/dev/disk/by-label/NIXOS_BOOT";
      fsType = "vfat";
    };
  };

  # Host-specific state persistence
  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/open-webui"
      "/var/lib/openclaw"
      "/var/lib/agent-zero"
      "/var/lib/anythingllm"
    ];
  };

  # Workload Specialisations (Saves memory by default)
  specialisation = {
    agents.configuration = {
      my.containers = {
        open-webui.enable = lib.mkForce true;
        openclaw.enable = lib.mkForce true;
        agent-zero.enable = lib.mkForce true;
        anythingllm.enable = lib.mkForce true;
      };
    };
  };

  system.stateVersion = "25.11";
}
