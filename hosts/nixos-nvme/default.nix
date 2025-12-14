{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/intel-compute.nix
    ./modules/printing.nix
  ];

  ############################
  ## Nix / flakes / unfree  ##
  ############################

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

  ############################
  ## Boot / basic system    ##
  ############################

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 8;
      };
      efi.canTouchEfiVariables = true;
    };

    blacklistedKernelModules = [ "pcspkr" "snd_pcsp" ];
    consoleLogLevel = 0;
    kernelParams = [
      "quiet" "loglevel=0" "udev.log_level=3"
      "acpi_osi=Linux" "intel_idle.max_cstate=1"
      "i915.enable_psr=0"
      "snd_hda_intel.power_save=0" "snd_hda_intel.power_save_controller=N"
    ];
  };

  networking.hostName = "nixos-nvme";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Dublin";
  i18n.defaultLocale = "en_IE.UTF-8";
  console.keyMap = "us";
  fonts.fontconfig.enable = true;

  ############################
  ## Hardware / Firmware    ##
  ############################

  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableAllFirmware = true;

  ############################
  ## Desktop Environment    ##
  ############################

  xdg.portal = {
    enable = true;
    extraPortals = [ 
      pkgs.xdg-desktop-portal-cosmic 
      pkgs.xdg-desktop-portal-gtk 
    ];
    config.common.default = "cosmic";
  };

  services = {
    displayManager.cosmic-greeter.enable = true;
    desktopManager.cosmic.enable = true;
    system76-scheduler.enable = true;

    ollama.enable = true;
    
    flatpak.enable = true;

    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    dbus.enable = true;

    # Keep Avahi for network discovery
    avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        userServices = true;
      };
    };
  };

  programs = {
    xwayland.enable = true;
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };

  # Build in RAM (Speed Boost)
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "75%";
  
  # Massive Swap for 64GB RAM
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50; 
  };

  # Ensure Ollama starts automatically
  systemd.services.ollama.wantedBy = [ "multi-user.target" ];

  ############################
  ## Users / sudo           ##
  ############################

  users.users.martin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "podman" "video" "render" ];
    initialPassword = "changeme";
  };
  
  security = {
    sudo.wheelNeedsPassword = true;
    rtkit.enable = true;
    polkit.enable = true;
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

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    btop
    unzip
    zip
    file
    pciutils
    libsForQt5.qt5.qtwayland
    qt6.qtwayland
    cosmic-files
    cosmic-term
    cosmic-edit
    cosmic-store
    cosmic-screenshot
    cosmic-settings
    cosmic-randr
    cosmic-applibrary
    cosmic-comp
    cosmic-panel
    cosmic-greeter
    podman
    podman-tui
    docker-compose
  ];

  system.stateVersion = "25.11";
}
