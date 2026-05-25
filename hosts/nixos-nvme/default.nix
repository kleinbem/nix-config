{
  pkgs,
  lib,
  config,
  inputs,
  self,
  myInventory,
  ...
}:

{
  imports = [
    inputs.nix-hardware.nixosModules.nixos-nvme
    inputs.nix-hardware.nixosModules.intel-compute
    "${self}/modules/nixos/common.nix"
    "${self}/modules/nixos/hosts.nix"
    "${self}/modules/nixos/default.nix"
    "${self}/users/martin/nixos.nix"
    "${self}/users/dhirujaan/nixos.nix"
    inputs.nix-presets.nixosModules.n8n
    inputs.nix-presets.nixosModules.code-server
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.dashboard
    inputs.nix-presets.nixosModules.qdrant
    inputs.nix-presets.nixosModules.playground
    inputs.nix-presets.nixosModules.caddy
    inputs.nix-presets.nixosModules.comfyui
    inputs.nix-presets.nixosModules.langfuse
    inputs.nix-presets.nixosModules.langflow
    inputs.nix-presets.nixosModules.vllm
    inputs.nix-presets.nixosModules.monitoring
    inputs.nix-presets.nixosModules.monitoring-node
    inputs.nix-presets.nixosModules.litellm
    inputs.nix-presets.nixosModules.loki
    inputs.nix-presets.nixosModules.crowdsec
    inputs.nix-presets.nixosModules.netdata
    inputs.nix-presets.nixosModules.authelia
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.agent-team
    inputs.nix-presets.nixosModules.cups
    inputs.nix-presets.nixosModules.github-runner
    inputs.nix-presets.nixosModules.ollama
    inputs.nix-presets.nixosModules.syncthing
    inputs.nix-presets.nixosModules.backup
    inputs.nix-presets.nixosModules.paperless

    "${self}/modules/nixos/persistence.nix"
    ./secrets.nix
    "${self}/modules/nixos/apps.nix"
    "${self}/modules/nixos/snapper.nix"
    "${self}/modules/nixos/disko.nix"
    "${self}/modules/nixos/data-disk.nix"
    inputs.disko.nixosModules.disko
    ./ai.nix
    ./specialisations.nix
  ];

  # --- Stateless Root / Var ---
  fileSystems = {
    "/" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=4G"
        "mode=755"
      ];
      neededForBoot = true;
    };

    "/var" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=8G"
        "mode=755"
      ];
      neededForBoot = true;
    };

    "/nix".neededForBoot = true;
    "/nix/persist".neededForBoot = true;
  };

  # --- Persistent Identity (Declarative Symlinks) ---
  environment = {
    etc = {
    };

    # Global environment variables
    variables = {
      CUPS_SERVER = myInventory.network.nodes.cups.ip;
    };

    systemPackages = with pkgs; [
      sops
      age
      age-plugin-yubikey
      age-plugin-tpm
      libfido2
      pam_u2f
      sbctl
      niv
      cups # Client tools (lpstat, etc.)
      yubikey-personalization
      openssl
      parted
      dosfstools
      tio # serial terminal (USB-TTL, embedded devices)
    ];
  };

  # --- Container Configuration ---
  my = {
    containers = {
      n8n = {
        enable = true;
        standaloneRunner = true;
        ip = "${myInventory.network.nodes.n8n.ip}/24";
        hostDataDir = "/var/lib/images/n8n";
        memoryLimit = "6G";
        secretsFile = config.sops.templates."n8n.env".path;
        noteDirs = {
          repos = config.my.developDir;
        };
        tls = {
          enable = true;
          serverPort = 5678;
          upstreams = [
            {
              name = "vllm";
              target = myInventory.network.nodes.vllm.ip;
              port = 8000;
            }
            {
              name = "qdrant";
              target = myInventory.network.nodes.qdrant.ip;
              port = 6333;
            }
          ];
        };
      };

      code-server = {
        enable = false;
        ip = "${myInventory.network.nodes.code-server.ip}/24";
        hostDataDir = config.my.developDir;
        user = config.my.username;
        memoryLimit = "8G"; # IDEs are heavy
      };

      open-webui = {
        enable = false;
        ip = "${myInventory.network.nodes.open-webui.ip}/24";
        hostDataDir = "/var/lib/images/open-webui";
        vllmUrl = "http://localhost:8000/v1"; # Via mTLS sidecar → vLLM
        memoryLimit = "4G";
        secretsFile = config.sops.templates."openwebui.env".path;
        tls = {
          enable = true;
          serverPort = 8080;
          upstreams = [
            {
              name = "vllm";
              target = myInventory.network.nodes.vllm.ip;
              port = 8000;
            }
            {
              name = "langfuse";
              target = myInventory.network.nodes.langfuse.ip;
              port = 3000;
            }
          ];
        };
      };

      dashboard = {
        enable = true;
        ip = "${myInventory.network.nodes.dashboard.ip}/24";
        hostBridgeIp = myInventory.network.nodes.cockpit.ip;
        memoryLimit = "1G";
        secretsFile = config.sops.templates."homepage.env".path;
      };

      qdrant = {
        enable = false;
        ip = "${myInventory.network.nodes.qdrant.ip}/24";
        hostDataDir = "/var/lib/images/qdrant";
        memoryLimit = "2G";
        tls = {
          enable = true;
          serverPort = 6333;
          upstreams = [ ];
        };
      };

      # --- Advanced AI Suite (Managed via ai.nix) ---

      loki = {
        enable = false;
        ip = "${myInventory.network.nodes.loki.ip}/24";
        hostDataDir = "/var/lib/images/loki";
      };

      monitoring = {
        enable = false;
        ip = "${myInventory.network.nodes.monitoring.ip}/24";
        hostDataDir = "/var/lib/images/monitoring";
        # Automatically scrape the host and important infrastructure nodes
        nodeTargets = [
          myInventory.network.nodes.cockpit.ip
          myInventory.hosts.router-1.ip
          myInventory.hosts.router-2.ip
        ];
        vllmTargets = [ myInventory.network.nodes.vllm.ip ];
      };

      openclaw = {
        enable = false;
        ip = "${myInventory.network.nodes.openclaw.ip}/24";
        hostDataDir = "/var/lib/images/openclaw";
      };
    };

    containers = {
      caddy = {
        enable = lib.mkForce true;
        ip = "${myInventory.network.nodes.caddy.ip}/24";
        hostDataDir = "/var/lib/caddy";
        memoryLimit = "512M";
      };

      crowdsec = {
        enable = true;
        ip = "${myInventory.network.nodes.crowdsec.ip}/24";
        hostDataDir = "/var/lib/images/crowdsec";
      };

      netdata = {
        enable = false;
        ip = "${myInventory.network.nodes.netdata.ip}/24";
      };

      authelia = {
        enable = false;
        ip = "${myInventory.network.nodes.authelia.ip}/24";
        hostDataDir = "/var/lib/images/authelia";
        domain = "local";
      };

      cups = {
        enable = false;
        ip = "${myInventory.network.nodes.cups.ip}/24";
      };

      github-runner = {
        enable = false; # Moved to workload profiles
        ip = "${myInventory.network.nodes.github-runner.ip}/24";
        hostDataDir = "/var/lib/images/github-runner";
        secretsFile = config.sops.secrets.local_github_actions_runner.path;
      };

      ollama = {
        enable = false; # Disabled by default; enabled in playground specialisation
        ip = "${myInventory.network.nodes.ollama.ip}/24";
        hostDataDir = "/var/lib/images/ollama";
      };

      syncthing = {
        enable = true;
        ip = "${myInventory.network.nodes.syncthing.ip}/24";
        hostDataDir = "/var/lib/images/syncthing";
        # secretsFile = config.sops.templates."syncthing.env".path;
        vaults = {
          "/home/${config.my.username}/Documents/Notes" = "/home/${config.my.username}/Documents/Notes";
          "/home/${config.my.username}/Develop" = "/home/${config.my.username}/Develop";
        };
      };

      backup = {
        enable = true;
        ip = "10.85.46.128/24";
        passwordFile = config.sops.secrets.restic_password.path;
        systemPasswordFile = config.sops.secrets.restic_system_password.path;
        rcloneConfigFile = config.sops.secrets.rclone_config.path;
        targets = {
          "/home" = config.my.home;
          "/var/lib/images/n8n" = "/var/lib/images/n8n";
        };
        systemTargets = {
          "/etc/ssh" = "/etc/ssh";
          "/var/lib/sops" = "/var/lib/sops";
          "/nix/persist/var/lib/sbctl" = "/nix/persist/var/lib/sbctl";
          "/var/lib/caddy" = "/var/lib/caddy";
          "/var/lib/images" = "/var/lib/images";
        };
      };

      paperless = {
        enable = false;
        ip = "${myInventory.network.nodes.paperless.ip}/24";
        hostDataDir = "/mnt/data/Archive/Paperless";
        hostConsumptionDir = "/mnt/data/Archive/Inbox";
        passwordFile = config.sops.secrets.paperless_password.path;
      };
    };

    monitoring.node.enable = true;

    desktop = {
      enable = false;
      gnome.enable = true;
    };
    virtualisation.enable = true;
    services = {
      printing.enable = false; # Handled by the cups container
    };
    android.enable = true;
  };

  systemd = {
    services = {
      # Caddy PKI: Copy the root CA cert to the user's home for Firefox trust
      # This runs on the host and is fail-safe to prevent restart loops.
      "container@caddy".postStart = ''
        if [ -f /var/lib/caddy/pki/authorities/local/root.crt ]; then
          mkdir -p /home/${config.my.username}/.pki
          cp -f /var/lib/caddy/pki/authorities/local/root.crt /home/${config.my.username}/.pki/caddy-root.crt
          chown ${config.my.username}:users /home/${config.my.username}/.pki/caddy-root.crt
          echo "✅ Caddy Root CA copied to user profile."
        else
          echo "⚠️ Caddy Root CA not found yet. Skipping copy."
        fi
      '';

      crowdsec-firewall-bouncer = {
        after = [ "container@crowdsec.service" ];
        serviceConfig = {
          ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 30); do ${pkgs.netcat-openbsd}/bin/nc -z ${myInventory.network.nodes.crowdsec.ip} ${toString myInventory.network.nodes.crowdsec.port} && exit 0 || sleep 5; done; exit 1'";
          Restart = "on-failure";
          RestartSec = "10s";
          TimeoutStartSec = "180";
        };
      };

      "container@crowdsec".preStart = ''
        mkdir -p /var/lib/images/crowdsec
        if [ ! -f /var/lib/images/crowdsec/bouncer-key ]; then
          tr -dc A-Za-z0-9 </dev/urandom | head -c 32 > /var/lib/images/crowdsec/bouncer-key
          chmod 600 /var/lib/images/crowdsec/bouncer-key
        fi
      '';
    };

    # IMAGE STATE STORAGE
    tmpfiles.rules = [
      "d /var/lib/images 0755 root root - -" # Create parent, non-recursive
      "d /var/lib/images/n8n 0755 root root - -"
      "d /var/lib/images/playground 0755 martin users - -" # Ensure you own your playground
      "d /var/lib/images/caddy 0755 root root - -"
      "d /var/lib/images/litellm 0755 root root - -"
      "d /var/lib/images/loki 0755 root root - -"
      "d /var/lib/images/crowdsec 0755 root root - -"
      "d /var/lib/images/monitoring 0755 root root - -"
      "d /var/lib/images/monitoring/db 0755 root root - -"
      "d /var/lib/images/monitoring/grafana 0755 root root - -"
      "d /var/lib/images/qdrant 0755 root root - -"
      "d /var/lib/images/open-webui 0755 root root - -"
      "d /var/lib/images/lmstudio 0750 martin users - -"
      "d /var/lib/images/netdata 0755 root root - -"
      "d /var/lib/images/netdata/cache 0755 root root - -"
      "d /var/lib/images/netdata/lib 0755 root root - -"
      "d /var/lib/images/langfuse 0755 root root - -"
      "d /var/lib/images/langfuse/db 0755 root root - -"
      "d /var/lib/images/github-runner 0755 1000 100 - -"
      "d /var/lib/images/syncthing 0755 root root - -"
    ];
  };

  home-manager.users.${config.my.username} = import "${self}/users/martin/home.nix";
  home-manager.users.dhirujaan = import "${self}/users/dhirujaan/home.nix";

  boot = {
    kernelPackages = pkgs.linuxPackages_zen;
    # Force the JMicron JMS581 (152d:0581) USB-NVMe bridge out of UAS into BOT mode.
    # Its UAS firmware resets under sustained write load, causing I/O errors and
    # filesystem corruption when provisioning the Orin SSD over the USB enclosure.
    kernelParams = [ "usb-storage.quirks=152d:0581:u" ];
    initrd = {
      availableKernelModules = [
        "nvme"
        "xhci_pci"
        "thunderbolt"
        "usb_storage"
        "sd_mod"
        "ahci"
      ];
      kernelModules = [
        "usbhid"
        "hid_generic"
      ];
      systemd.enable = true;
      systemd.tpm2.enable = true;
      services.lvm.enable = true;
    };
    loader = {
      systemd-boot.enable = lib.mkForce false;
      systemd-boot.configurationLimit = 15;
      efi.canTouchEfiVariables = true;
    };
    lanzaboote = {
      enable = true;
      pkiBundle = "/nix/persist/var/lib/sbctl";
    };
    # Kernel parameters now handled by kernel.nix and audit.nix
    # i915 enhancements moved to kernel.nix
    tmp.useTmpfs = true;
    tmp.tmpfsSize = "8G";

  };
  nix = {
    # Distributed Builds: Use Orin Nano for native aarch64 builds
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "10.85.46.104"; # Orin Nano via NetBird Mesh
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

  # Cross-compilation: fallback to emulation if Orin is offline
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  boot.binfmt.registrations."aarch64-linux".fixBinary = true; # Required for disko-install chroot

  # Allow the nix sandbox to access the qemu binfmt interpreter for aarch64 builds
  nix.settings.extra-sandbox-paths = [ "/run/binfmt" ];

  # Host-level CrowdSec Firewall Bouncer
  services.crowdsec-firewall-bouncer = {
    enable = true;
    secrets.apiKeyPath = "/var/lib/images/crowdsec/bouncer-key";
    settings = {
      api_url = "http://${myInventory.network.nodes.crowdsec.ip}:8080/";
      api_keyfile = "/var/lib/images/crowdsec/bouncer-key";
    };
  };

  hardware = {
    cpu.intel.updateMicrocode = true;
    enableRedistributableFirmware = true;
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        intel-compute-runtime
        libvdpau-va-gl
      ];
    };
  };

  networking = {
    hostName = "nixos-nvme";
    # TODO: remove once OpenWrt router is enrolled in NetBird and pushes DNS nameserver rules.
    # NetBird peer IPs are stable, but this bypasses proper split-DNS.
    hosts."100.117.61.169" = [
      "orin-nano.netbird.cloud"
      "orin-nano"
    ];
    networkmanager = {
      enable = true;
      plugins = [ pkgs.networkmanager-openvpn ];
    };
    # Fix Routing for the Ricoh Printer subnet (10.0.x.x)
    interfaces.wlo1.ipv4.routes = [
      {
        address = "10.0.0.0";
        prefixLength = 16;
      }
    ];
    firewall = {
      enable = true;
      # Open all ports that Caddy is proxying to allow external access
      allowedTCPPorts = lib.mapAttrsToList (_: node: node.externalPort) (
        lib.filterAttrs (_: v: v ? externalPort) myInventory.network.nodes
      );

      # Zero Trust: NetBird is NOT blanket-trusted.
      # Only specific ports are open over the tunnel.
      interfaces."wt0".allowedTCPPorts = [
        22 # SSH
        443 # Caddy HTTPS (access all services via reverse proxy)
        9091 # Cockpit
      ];
      # Tang (LUKS auto-unlock for orin-nano) on the LAN/Wi-Fi interface only
      interfaces."wlo1".allowedTCPPorts = [ 7654 ];
      allowedTCPPortRanges = [
        {
          from = 1714;
          to = 1764;
        } # KDE Connect (GSConnect)
      ];
      allowedUDPPortRanges = [
        {
          from = 1714;
          to = 1764;
        } # KDE Connect (GSConnect)
      ];
    };
    nftables.enable = true;
  };

  services = {
    # Tang server for headless LUKS auto-unlock of fleet hosts (e.g. orin-nano clevis).
    # LAN-only; security comes from network reachability + the encrypted JWE blob, not auth.
    tang = {
      enable = true;
      ipAddressAllow = [ "10.0.0.0/16" ];
    };

    journald.extraConfig = ''
      SystemMaxUse=500M
      SystemMaxFileSize=50M
      MaxRetentionSec=1month
    '';

    netbird = {
      enable = true;
      ui.enable = true; # Adds the NetBird GUI/Tray Icon
    };
    pcscd.enable = true;
    fprintd.enable = true;
    udev.packages = [
      pkgs.yubikey-personalization
      pkgs.libfido2
    ];
    udev.extraRules = ''
      # Use kyber scheduler for NVMe to improve latency
      ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="kyber"
    '';
    fwupd.enable = true;
    irqbalance.enable = true;
    btrfs.autoScrub = {
      enable = true;
      interval = "weekly";
      fileSystems = [
        "/home"
        "/nix"
      ];
    };
    fstrim.enable = true;

    # --- High-Performance Scheduling (Official Nixpkgs) ---
    scx = {
      enable = true;
      scheduler = "scx_rusty"; # High-performance rust-based scheduler (successor to BORE)
    };
  };

  system.stateVersion = "25.11";
  my.security.ai-hardening.enable = true;

}
