{
  pkgs,
  lib,
  inputs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/core.nix
    ../../modules/nixos/desktop.nix
    ../../modules/nixos/intel-compute.nix
    ../../modules/nixos/printing.nix
    ../../modules/nixos/users.nix
    ../../modules/nixos/scripts.nix
    ../../modules/nixos/security.nix
  ];

  # ==========================================
  # 1. CORE SYSTEM & BOOT
  # ==========================================
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    loader = {
      timeout = 2; # Fast boot
      systemd-boot = {
        enable = true;
        configurationLimit = 8;
        memtest86.enable = true; # Bootable memory test
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
      "i915.enable_psr=0"
      "snd_hda_intel.power_save=0"
      "snd_hda_intel.power_save_controller=N"
    ];

    tmp.useTmpfs = true;
    tmp.tmpfsSize = "75%";

    # Network Tuning & Kernel Optimizations
    kernel.sysctl = {
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.tcp_congestion_control" = "bbr";

      # ClamAV On-Access Scanning (essential for large directories)
      "fs.inotify.max_user_watches" = 524288;

      # Desktop Responsiveness
      "vm.swappiness" = 10;
      "vm.vfs_cache_pressure" = 50;
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
    networkmanager = {
      enable = true;
      # 25.11 requires explicit plugins for VPNs
      plugins = [ pkgs.networkmanager-openvpn ];
    };

    # Switch to Firewalld for dynamic port management (Reverse Shells / Listeners)
    firewall.enable = false;
    nftables.enable = true;
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
      # loadModels = [ ... ]; # Too large for declarative download (>40GB).
      # Run 'ollama pull llama3.1:70b-instruct-q4_K_M' manually.
      # Note: Intel iGPU acceleration for Ollama via IPEX-LLM/Vulkan
      # is not yet upstreamed in nixpkgs (late 2025). Using CPU for now.
    };

    open-webui = {
      enable = true;
      port = 8080;
      environment = {
        # Optional: Enable if you want to expose to LAN, otherwise localhost only
        # OLLAMA_BASE_URL = "http://127.0.0.1:11434";
      };
    };

    # ==========================================
    # 8. HARDWARE TOKENS
    # ==========================================
    pcscd.enable = true;
    fprintd.enable = true;
    udev.packages = [
      pkgs.yubikey-personalization
      pkgs.libfido2
    ];

    # Firmware Updates
    fwupd.enable = true;

    # Dynamic Firewall (Firewalld)
    firewalld.enable = true;

    # Btrfs Maintenance
    btrfs.autoScrub = {
      enable = true;
      interval = "weekly";
      fileSystems = [
        "/home"
        "/nix"
      ];
    };

    # SSD Optimization (Trim)
    fstrim.enable = true;
  };

  # ==========================================
  # FIX: Relocate massive AI state to /images
  # ==========================================
  systemd = {
    tmpfiles.rules = [
      "d /images/ollama 0750 ollama ollama - -"
      "d /images/open-webui 0750 open-webui open-webui - -"
    ];

    # Override services to use static users (resolves bind mount permission issues)
    services.ollama.serviceConfig.DynamicUser = lib.mkForce false;
    services.open-webui.serviceConfig.DynamicUser = lib.mkForce false;
  };

  fileSystems = {
    "/var/lib/ollama" = {
      device = "/images/ollama";
      options = [ "bind" ];
    };
    "/var/lib/private/ollama" = {
      device = "/images/ollama";
      options = [ "bind" ];
    };
    "/var/lib/open-webui" = {
      device = "/images/open-webui";
      options = [ "bind" ];
    };
  };
  # (Note: open-webui might use /var/lib/private/open-webui depending on DynamicUser settings)
  # But the module usually sets StateDirectory=open-webui which maps to /var/lib/open-webui
  # or /var/lib/private/open-webui if DynamicUser is on.
  # Let's cover the StateDirectory path safely.

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
    lm_sensors # Hardware sensors (Fanless temp monitoring)
  ];

  system.stateVersion = "25.11";
}
