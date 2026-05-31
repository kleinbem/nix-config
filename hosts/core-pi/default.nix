# core-pi — Raspberry Pi 5
{
  inputs,
  self,
  myInventory,
  lib,
  pkgs,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
  # Initrd gate: poll Tang until it answers before clevis runs, sidestepping the
  # initrd network race. MUST be added to boot.initrd.systemd.storePaths.
  waitForTang = pkgs.writeShellScript "wait-for-tang" ''
    i=0
    while [ "$i" -lt 30 ]; do
      if ${pkgs.curl}/bin/curl -fsS -m 2 -o /dev/null http://10.0.0.5:7654/adv; then
        echo "wait-for-tang: Tang reachable after $i retry(ies)"
        exit 0
      fi
      echo "wait-for-tang: Tang not reachable yet ($i)"
      ${pkgs.coreutils}/bin/sleep 1
      i=$((i + 1))
    done
    echo "wait-for-tang: Tang still unreachable; continuing (clevis falls back to passphrase)"
    exit 0
  '';
in
{
  imports = [
    inputs.nix-hardware.nixosModules.rpi5
    inputs.disko.nixosModules.disko
    ./disko.nix
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"
    "${self}/modules/nixos/persistence.nix"
    "${self}/modules/nixos/virtualisation.nix"
    "${self}/modules/nixos/pki.nix"
    "${self}/modules/nixos/networking.nix"
    "${self}/modules/nixos/network-routing.nix"
    "${self}/modules/nixos/services/rpi-eeprom.nix"
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
    "/nix".neededForBoot = true;
    "/nix/persist".neededForBoot = true;
  };

  # Enable systemd in initrd for LUKS auto-unlock
  boot.initrd = {
    network = {
      enable = true;
      ssh = {
        enable = true;
        port = 2222;
        authorizedKeys = [
          keys.ssh.yubikey
          keys.ssh.fido2
          keys.ssh.fido2-backup
        ];
        hostKeys =
          let
            key = "/etc/secrets/initrd/ssh_host_ed25519_key";
          in
          if builtins.pathExists key then [ key ] else [ ];
      };
    };

    systemd = {
      enable = true;
      # Bring up the wired NIC in initrd so clevis can reach the Tang server.
      network = {
        enable = true;
        networks."10-lan" = {
          matchConfig.Name = "en* eth*";
          networkConfig = {
            DHCP = "no";
            Address = "10.0.0.20/16";
            Gateway = "10.0.0.1";
          };
        };
      };

      # Gate clevis on Tang actually being reachable.
      storePaths = [ waitForTang ];

      services.wait-for-tang = {
        description = "Wait for Tang reachability before clevis LUKS unlock";
        after = [ "systemd-networkd.service" ];
        before = [ "cryptsetup-clevis-core_crypt.service" ];
        wantedBy = [ "cryptsetup-clevis-core_crypt.service" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = 120;
          ExecStart = waitForTang;
        };
      };

      services."cryptsetup-clevis-core_crypt" = {
        after = [ "wait-for-tang.service" ];
        wants = [ "wait-for-tang.service" ];
      };
    };

    # Clevis LUKS auto-unlock configuration
    clevis = {
      enable = true;
      useTang = true;
      devices."core_crypt".secretFile = ./core_crypt.jwe;
    };
  };

  # Disko configuration defaults
  disko.devices.disk.main.device = lib.mkDefault "/dev/mmcblk0";
  _module.args.device = "/dev/mmcblk0";

  environment.systemPackages = with pkgs; [
    clevis # LUKS Tang binding — run `clevis luks bind -d /dev/mmcblk0p2 tang '{"url":"http://10.0.0.5:7654"}'`
    jose # JSON Object Signing and Encryption
  ];

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
  my.services.tang.enable = true;
}
