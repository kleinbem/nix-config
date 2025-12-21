{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/intel-compute.nix
    ./modules/printing.nix
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
    blacklistedKernelModules = [ "pcspkr" "snd_pcsp" ];
    consoleLogLevel = 0;
    kernelParams = [
      "quiet" "loglevel=0" "udev.log_level=3"
      "acpi_osi=Linux" "intel_idle.max_cstate=1"
      "i915.enable_psr=0"
      "snd_hda_intel.power_save=0" "snd_hda_intel.power_save_controller=N"
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
    
    # Enable Intel iGPU Compute for AI
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        intel-compute-runtime 
      ];
    };
  };

  networking = {
    hostName = "nixos-nvme";
    networkmanager.enable = true;
  };

  time.timeZone = "Europe/Dublin";
  i18n.defaultLocale = "en_IE.UTF-8";
  console.keyMap = "us";

  # ==========================================
  # 3. NIX SETTINGS
  # ==========================================
  nixpkgs.config.allowUnfree = true;
  nix = {
    registry.nixpkgs.flake = inputs.nixpkgs;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      substituters = [ "https://cache.nixos.org" ];
      trusted-public-keys = [ "cache.nixos.org-1:Ik/ZBziETSRre3nCpv7l4WwhDD5OhoOx9LG/mIJV6Hg=" ];
      download-buffer-size = 1073741824;
      max-jobs = "auto";
      cores = 0;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # ==========================================
  # 4. DESKTOP (COSMIC)
  # ==========================================
  services = {
    displayManager.cosmic-greeter.enable = true;
    desktopManager.cosmic.enable = true;
    system76-scheduler.enable = true;
    
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
    
    dbus.enable = true;
    avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        userServices = true;
      };
    };
  };

  xdg.portal = {
    enable = true;
    extraPortals = [ 
      pkgs.xdg-desktop-portal-cosmic 
      pkgs.xdg-desktop-portal-gtk 
    ];
    config.common.default = "cosmic";
  };

  fonts.fontconfig.enable = true;
  programs.xwayland.enable = true;

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
  # 6. USERS & SECURITY
  # ==========================================
  users.users.root = {
    initialPassword = "backup-root-password";
  };

  users.users.martin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "podman" "video" "render" "libvirtd" "kvm" ];
    hashedPasswordFile = config.sops.secrets.martin_password.path;
  };

  security = {
    sudo.wheelNeedsPassword = true;
    rtkit.enable = true;
    polkit.enable = true;
    pam.u2f = {
      enable = true;
      cue = true; 
    };
  };

  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };

  # ==========================================
  # 7. SERVICES & AI (Ollama Brain)
  # ==========================================
  services.ollama = {
    enable = true;
    acceleration = null; 
    host = "0.0.0.0";    
    
    # Models will be downloaded but NOT loaded into RAM until requested
    loadModels = [
      "llama3.1:70b-instruct-q4_K_M" 
      "llama3.2:3b"                   
      "nomic-embed-text"              
    ];
  };

  # ==========================================
  # 8. HARDWARE TOKENS
  # ==========================================
  services.pcscd.enable = true;
  services.udev.packages = [ 
    pkgs.yubikey-personalization 
    pkgs.libfido2 
  ];
  
  # ==========================================
  # 9. SECRETS (SOPS)
  # ==========================================
  sops = {
    defaultSopsFile = ./secrets.yaml;
    defaultSopsFormat = "yaml";
    age.keyFile = "/home/martin/.config/sops/age/keys.txt";
    
    package = pkgs.runCommand "sops-with-plugins" {
      nativeBuildInputs = [ pkgs.makeWrapper ];
    } ''
      mkdir -p $out/bin
      makeWrapper ${pkgs.sops}/bin/sops $out/bin/sops \
        --prefix PATH : "${pkgs.age-plugin-yubikey}/bin"
      makeWrapper ${inputs.sops-nix.packages.${pkgs.system}.sops-install-secrets}/bin/sops-install-secrets $out/bin/sops-install-secrets \
        --prefix PATH : "${pkgs.age-plugin-yubikey}/bin"
    '';

    secrets.martin_password = {
      neededForUsers = true;
    };
  };

  # ==========================================
  # 10. SYSTEM PACKAGES
  # ==========================================
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  
  services.flatpak.enable = true;
  programs.fuse.userAllowOther = true;

  environment.systemPackages = with pkgs; [
    # Core Tools
    git curl wget htop btop unzip zip file pciutils
    
    # Desktop Utilities
    libsForQt5.qt5.qtwayland qt6.qtwayland
    
    # Cosmic Apps
    cosmic-files cosmic-term cosmic-edit cosmic-store
    cosmic-screenshot cosmic-settings cosmic-randr
    cosmic-applibrary cosmic-comp cosmic-panel cosmic-greeter
    
    # Containers
    podman podman-tui docker-compose
    
    # Security & Tokens
    sops age age-plugin-yubikey
    libfido2 pam_u2f

    # AI Diagnostics
    intel-gpu-tools 
  ];

  system.stateVersion = "25.11";
}