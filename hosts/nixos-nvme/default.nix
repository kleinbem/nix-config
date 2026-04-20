{
  pkgs,
  lib,
  config,
  inputs,
  myInventory,
  ...
}:

{
  imports = [
    inputs.nix-hardware.nixosModules.nixos-nvme
    inputs.nix-hardware.nixosModules.intel-compute
    ../../modules/nixos/common.nix
    ../../modules/nixos/hosts.nix
    ../../modules/nixos/default.nix
    ../../modules/nixos/options.nix
    ../../users/martin/nixos.nix
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
    inputs.nix-presets.nixosModules.falco
    inputs.nix-presets.nixosModules.netdata
    inputs.nix-presets.nixosModules.authelia
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.waydroid
    inputs.nix-presets.nixosModules.android-emulator
    ../../modules/nixos/persistence.nix
    ./secrets.nix
    ../../modules/nixos/apps.nix
    ../../modules/nixos/snapper.nix
    ../../modules/nixos/disko.nix
    ../../modules/nixos/data-disk.nix
    inputs.disko.nixosModules.disko
    ./ai.nix
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

    # Persistence Anchor and Images are now managed by disko.nix
    "/nix".neededForBoot = true;
    "/nix/persist".neededForBoot = true;
  };

  # --- Persistent Identity (Declarative Symlinks) ---
  environment.etc = {
    "machine-id".source = lib.mkForce "/nix/persist/etc/machine-id";
  };

  # --- Container Configuration ---
  my = {
    containers = {
      n8n = {
        enable = true;
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
        enable = true;
        ip = "${myInventory.network.nodes.code-server.ip}/24";
        hostDataDir = config.my.developDir;
        user = config.my.username;
        memoryLimit = "8G"; # IDEs are heavy
      };

      open-webui = {
        enable = true;
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
        hostBridgeIp = "10.85.46.1";
        memoryLimit = "1G";
        secretsFile = config.sops.templates."homepage.env".path;
      };

      qdrant = {
        enable = true;
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
        enable = true;
        ip = "${myInventory.network.nodes.loki.ip}/24";
        hostDataDir = "/var/lib/images/loki";
      };

      monitoring = {
        enable = true;
        ip = "${myInventory.network.nodes.monitoring.ip}/24";
        hostDataDir = "/var/lib/images/monitoring";
        # Automatically scrape the host and important AI nodes
        nodeTargets = [ "10.85.46.1" ];
        vllmTargets = [ "10.85.46.111" ];
      };

      falco = {
        enable = true;
        ip = "${myInventory.network.nodes.falco.ip}/24";
        sidekickIp = "${myInventory.network.nodes.falcosidekick.ip}/24";
      };

      netdata = {
        enable = true;
        ip = "${myInventory.network.nodes.netdata.ip}/24";
      };

      authelia = {
        enable = true;
        ip = "${myInventory.network.nodes.authelia.ip}/24";
        hostDataDir = "/var/lib/images/authelia";
        domain = "local";
      };
    };

    monitoring.node.enable = true;

    desktop.enable = true;
    virtualisation.enable = true;
    services = {
      printing.enable = true;
    };
  };

  # --- Persistence & System Services ---
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    SystemMaxFileSize=50M
    MaxRetentionSec=1month
  '';

  programs.waydroid-setup.enable = false;

  home-manager.users.${config.my.username} = import ../../users/martin/home.nix;

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
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
    };
    loader = {
      systemd-boot.enable = lib.mkForce false;
      systemd-boot.configurationLimit = 30;
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

    # Cross-compilation: build aarch64-linux on this x86_64 host
    binfmt.emulatedSystems = [ "aarch64-linux" ];
    binfmt.registrations."aarch64-linux".fixBinary = true; # Required for disko-install chroot
  };

  # IMAGE STATE STORAGE
  systemd.tmpfiles.rules = [
    "d /var/lib/images 0755 root root - -" # Create parent, non-recursive
    "d /var/lib/images/n8n 0755 root root - -"
    "d /var/lib/images/playground 0755 martin users - -" # Ensure you own your playground
    "d /var/lib/images/caddy 0755 root root - -"
    "d /var/lib/images/litellm 0755 root root - -"
    "d /var/lib/images/loki 0755 root root - -"
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
  ];

  hardware = {
    cpu.intel.updateMicrocode = true;
    enableAllFirmware = true;
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        libvdpau-va-gl
      ];
    };
  };

  networking = {
    hostName = "nixos-nvme";
    networkmanager = {
      enable = true;
      plugins = [ pkgs.networkmanager-openvpn ];
    };
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
      allowedTCPPortRanges = [
        {
          from = 1714;
          to = 1764;
        } # KDE Connect (Valent)
      ];
      allowedUDPPortRanges = [
        {
          from = 1714;
          to = 1764;
        } # KDE Connect (Valent)
      ];
    };
    nftables.enable = true;
  };

  services = {
    android-desktop-emulator = {
      enable = true;
      user = config.my.username;
    };
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
    fwupd.enable = true;
    btrfs.autoScrub = {
      enable = true;
      interval = "weekly";
      fileSystems = [
        "/home"
        "/nix"
      ];
    };
    fstrim.enable = true;
  };

  security.pki.certificateFiles = [ ./../../pki/caddy-root.crt ];

  environment.systemPackages = with pkgs; [
    sops
    age
    age-plugin-yubikey
    age-plugin-tpm
    libfido2
    pam_u2f
    sbctl
    niv
    yubikey-personalization
    android-tools
    scrcpy
    valent
    openssl
  ];

  system.stateVersion = "25.11";
  my.security.ai-hardening.enable = true;
}
