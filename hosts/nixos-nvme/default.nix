{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/hardware/intel-compute.nix
    ../../modules/nixos/bundle.nix
    ../../modules/nixos/common.nix
    ../../users/martin/nixos.nix

  ];

  # Enable Switchboard Modules
  my = {
    desktop.enable = true;
    services = {
      ai.enable = true;
      printing.enable = true;
      code-server.enable = true;
      silverbullet.enable = true;
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

    # Switch to Firewalld for dynamic port management (Reverse Shells / Listeners)
    # networking.firewall.enable = false; # Disabled static firewall to use firewalld instead
    firewall.enable = false;
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
    firewalld.enable = true;

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
  ];

  # ==========================================
  # 9. SECRETS (SOPS)
  # ==========================================
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";
    age.keyFile = "/home/martin/.config/sops/age/host.txt";
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
