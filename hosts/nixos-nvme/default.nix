{
  pkgs,
  lib,
  inputs,
  ...
}:

{
  imports = [
    inputs.nix-hardware.nixosModules.nixos-nvme
    inputs.nix-hardware.nixosModules.intel-compute
    ../../modules/nixos/default.nix
    ../../modules/nixos/common.nix
    ../../users/martin/nixos.nix
    inputs.nix-presets.nixosModules.n8n
    inputs.nix-presets.nixosModules.silverbullet
    inputs.nix-presets.nixosModules.code-server
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.dashboard
    inputs.nix-presets.nixosModules.ollama
    inputs.nix-presets.nixosModules.qdrant
    inputs.nix-presets.nixosModules.waydroid
    inputs.nix-presets.nixosModules.android-emulator
    ../../modules/nixos/persistence.nix
    ../../modules/nixos/apps.nix
    ../../modules/nixos/snapper.nix
    ../../modules/nixos/disko.nix
    inputs.disko.nixosModules.disko
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
    "/nix/persist".neededForBoot = true;
  };

  # --- Container Configuration ---
  # --- Container & Switchboard Configuration ---
  my = {
    containers = {
      n8n = {
        enable = true;
        ip = "10.85.46.99/24";
        hostBridge = "incusbr0";
        hostDataDir = "/home/martin/n8n-data";
        noteDirs = {
          silverbullet = "/home/martin/Develop/Notes";
          obsidian = "/home/martin/GoogleDrive/Obsidian";
          repos = "/home/martin/Develop/github.com/kleinbem";
        };
      };

      silverbullet = {
        enable = true;
        ip = "10.85.46.100/24";
        hostBridge = "incusbr0";
        hostDataDir = "/home/martin/Develop/Notes";
      };

      code-server = {
        enable = true;
        ip = "10.85.46.101/24";
        hostBridge = "incusbr0";
        hostDataDir = "/home/martin/Develop";
      };

      open-webui = {
        enable = true;
        ip = "10.85.46.102/24";
        hostBridge = "incusbr0";
        hostDataDir = "/home/martin/ai-data/open-webui";
        ollamaUrl = "http://10.85.46.104:11434";
      };

      dashboard = {
        enable = true;
        ip = "10.85.46.103/24";
        hostBridge = "incusbr0";
        hostBridgeIp = "10.85.46.1";
      };

      ollama = {
        enable = true;
        ip = "10.85.46.104/24";
        hostBridge = "incusbr0";
        hostDataDir = "/var/lib/images/ollama";
      };

      qdrant = {
        enable = true;
        ip = "10.85.46.105/24";
        hostBridge = "incusbr0";
        hostDataDir = "/var/lib/images/qdrant";
      };
    };

    desktop.enable = true;
    virtualisation.enable = true;
    services = {
      # ai.enable = true; # Replaced by container
      printing.enable = true;
      glances.enable = true;
    };
  };

  # --- Advanced Stateless Tuning ---
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    SystemMaxFileSize=50M
    MaxRetentionSec=1month
  '';

  programs.waydroid-setup.enable = true;

  home-manager.users.martin = import ../../users/martin/home.nix;

  # ==========================================
  # 1. CORE SYSTEM & BOOT
  # ==========================================
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    initrd.kernelModules = [
      "usbhid"
      "hid_generic"
    ];

    loader = {
      systemd-boot.enable = false; # Disabled for Lanzaboote
      systemd-boot.configurationLimit = 10; # Keep boot menu clean
      efi.canTouchEfiVariables = true;
    };
    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
    initrd.systemd.enable = true;
    kernelParams = [
      "i915.enable_guc=3"
      "i915.enable_fbc=1"
    ];

    tmp.useTmpfs = true;
    tmp.tmpfsSize = "8G"; # Plenty of space for large builds in your 64GB RAM
  };

  # ==========================================
  # 2. HARDWARE & FIRMWARE
  # ==========================================
  hardware = {
    cpu.intel.updateMicrocode = true;
    enableAllFirmware = true;
  };

  networking = {
    hostName = "nixos-nvme";
    networkmanager = {
      enable = true;
      # 25.11 requires explicit plugins for VPNs
      plugins = [ pkgs.networkmanager-openvpn ];
    };

    firewall.enable = true;
    firewall.trustedInterfaces = [ "tailscale0" ];
    nftables.enable = true;
  };

  # ==========================================
  # 8. HARDWARE TOKENS & MAINTENANCE
  # ==========================================
  services = {
    android-desktop-emulator = {
      enable = true;
      user = "martin";
    };

    tailscale.enable = true;

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

  # ==========================================
  # IMAGE STATE STORAGE
  # ==========================================
  systemd.tmpfiles.rules = [
    "d /var/lib/images 0755 root root - -"
    "z /var/lib/images 0755 root root - -"
    "d /var/lib/images/lmstudio 0750 martin users - -"
    "z /var/lib/images/lmstudio 0750 martin users - -"
    "d /var/lib/n8n 0755 martin users - -"
    "d /var/lib/images/ollama 0755 root root - -"
    "d /var/lib/images/ollama/models 0755 root root - -"
    "d /var/lib/images/qdrant 0755 root root - -"
  ];

  # ==========================================
  # 9. SECRETS (SOPS)
  # ==========================================
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";
    age.keyFile = "/nix/persist/var/lib/sops/age/host.txt";
    # Force systemd service generation (fixes missing sops-nix.service)
    useSystemdActivation = true;
    # Native plugin support (replaces manual wrapper)
    age.plugins = [
      pkgs.age-plugin-yubikey
      pkgs.age-plugin-tpm
    ];

    secrets.rclone_config = {
      owner = "martin";
    };
  };

  # ==========================================
  # 10. SYSTEM PACKAGES & PROGRAMS
  # ==========================================

  environment.systemPackages = with pkgs; [

    # Security & Tokens
    sops
    age
    age-plugin-yubikey
    age-plugin-tpm
    libfido2
    pam_u2f
    sbctl
    niv
    yubikey-personalization # Contains the Udev rules
    # libfido2 # Removed duplicate
  ];

  system.stateVersion = "25.11";
}
