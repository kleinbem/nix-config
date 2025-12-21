{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../../common/core.nix
    ../../common/cosmic.nix
    ../../common/intel-compute.nix
    ../../common/printing.nix
    ../../common/users.nix
  ];

  # ==========================================
  # 1. CORE SYSTEM & BOOT
  # ==========================================
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 8;
      };
      efi.canTouchEfiVariables = true;
    };
    initrd.systemd.enable = true;

    # Performance & Tweaks
    blacklistedKernelModules = [
      "pcspkr"
      "snd_pcsp"
    ];
    consoleLogLevel = 0;
    kernelParams = [
      "quiet"
      "loglevel=0"
      "udev.log_level=3"
      "acpi_osi=Linux"
      "intel_idle.max_cstate=1"
      "i915.enable_psr=0"
      "snd_hda_intel.power_save=0"
      "snd_hda_intel.power_save_controller=N"
    ];

    tmp.useTmpfs = true;
    tmp.tmpfsSize = "75%";

    # Network Tuning for Cluster Performance
    kernel.sysctl = {
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.tcp_congestion_control" = "bbr";
    };
  };

  # Massive Swap for 64GB RAM (Essential for 70B Model Overflow)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
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
    networkmanager.enable = true;
  };

  # ==========================================
  # 5. VIRTUALIZATION
  # ==========================================
  virtualisation = {
    libvirtd.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # ==========================================
  # 7. SERVICES & AI (Ollama Brain)
  # ==========================================
  services = {
    ollama = {
      enable = true;
      host = "0.0.0.0";
      loadModels = [
        "llama3.1:70b-instruct-q4_K_M"
        "llama3.2:3b"
        "nomic-embed-text"
      ];
    };

    # ==========================================
    # 8. HARDWARE TOKENS
    # ==========================================
    pcscd.enable = true;
    udev.packages = [
      pkgs.yubikey-personalization
      pkgs.libfido2
    ];
  };

  # ==========================================
  # 9. SECRETS (SOPS)
  # ==========================================
  sops = {
    defaultSopsFile = ./secrets.yaml;
    defaultSopsFormat = "yaml";
    age.keyFile = "/home/martin/.config/sops/age/keys.txt";

    package =
      pkgs.runCommand "sops-with-plugins"
        {
          nativeBuildInputs = [ pkgs.makeWrapper ];
        }
        ''
          mkdir -p $out/bin
          makeWrapper ${pkgs.sops}/bin/sops $out/bin/sops \
            --prefix PATH : "${pkgs.age-plugin-yubikey}/bin"
          makeWrapper ${
            inputs.sops-nix.packages.${pkgs.system}.sops-install-secrets
          }/bin/sops-install-secrets $out/bin/sops-install-secrets \
            --prefix PATH : "${pkgs.age-plugin-yubikey}/bin"
        '';
  };

  # ==========================================
  # 10. SYSTEM PACKAGES & PROGRAMS
  # ==========================================

  environment.systemPackages = with pkgs; [

    # Containers
    podman
    podman-tui
    docker-compose

    # Security & Tokens
    sops
    age
    age-plugin-yubikey
    libfido2
    pam_u2f

    # AI Diagnostics
    intel-gpu-tools
  ];

  system.stateVersion = "25.11";
}
