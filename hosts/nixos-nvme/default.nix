{
  pkgs,
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
    inputs.nix-presets.nixosModules.waydroid

  ];

  # --- Container Configuration ---
  # --- Container & Switchboard Configuration ---
  my = {
    containers = {
      n8n = {
        enable = true;
        ip = "10.85.46.99/24";
        hostBridge = "incusbr0";
        hostDataDir = "/home/martin/n8n-data";
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
    };

    desktop.enable = true;
    services = {
      # ai.enable = true; # Replaced by container
      printing.enable = true;
      glances.enable = true;
    };
    virtualisation.enable = true;
  };

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

    tmp.useTmpfs = true;
    tmp.tmpfsSize = "75%";
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
    nftables.enable = true;
  };

  # ==========================================
  # 8. HARDWARE TOKENS & MAINTENANCE
  # ==========================================
  services = {
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
  ];

  # ==========================================
  # 9. SECRETS (SOPS)
  # ==========================================
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";
    age.keyFile = "/var/lib/sops/age/host.txt";
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
