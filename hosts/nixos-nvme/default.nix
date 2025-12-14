{ config, pkgs, ... }:

let
  # Relative path to driver wrapper in the same folder
  ricohDriver = pkgs.callPackage ./ricoh-driver.nix {};
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  ############################
  ## Nix / flakes / unfree  ##
  ############################

  nixpkgs.config.allowUnfree = true;
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      substituters = [ "https://cache.nixos.org" ];
      trusted-public-keys = [ "cache.nixos.org-1:Ik/ZBziETSRre3nCpv7l4WwhDD5OhoOx9LG/mIJV6Hg=" ];
      # --- Performance Tweaks for 64GB RAM ---
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

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 8;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.blacklistedKernelModules = [ "pcspkr" "snd_pcsp" ];
  boot.consoleLogLevel = 0;
  boot.kernelParams = [
    "quiet" "loglevel=0" "udev.log_level=3"
    "acpi_osi=Linux" "intel_idle.max_cstate=1"
    "i915.enable_psr=0"
    "snd_hda_intel.power_save=0" "snd_hda_intel.power_save_controller=N"
  ];

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
  ## Graphics / Wayland     ##
  ############################

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      libva-vdpau-driver
      libvdpau-va-gl
      
      # --- AI/Compute Drivers for Intel iGPU ---
      intel-compute-runtime # OpenCL for Intel
      level-zero            # Level Zero API
      ocl-icd               # OpenCL Installable Client Driver
    ];
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  programs.xwayland.enable = true;
  
  # Combined Portal Configuration
  xdg.portal = {
    enable = true;
    extraPortals = [ 
      pkgs.xdg-desktop-portal-cosmic 
      pkgs.xdg-desktop-portal-gtk 
    ];
    config.common.default = "cosmic";
  };

  ############################
  ## Memory / swap          ##
  ############################

  # Massive Swap for 64GB RAM
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50; 
  };

  # Build in RAM (Speed Boost)
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "75%";

  ############################
  ## Local AI (Ollama)      ##
  ############################

  services.ollama = {
    enable = true;
    # On Intel iGPU, standard "rocm" or "cuda" acceleration won't work.
    # We rely on the CPU AVX2 optimizations (which are active) 
    # and the compute drivers added above.
  };
  
  # Ensure Ollama starts automatically
  systemd.services.ollama.wantedBy = [ "multi-user.target" ];

  ############################
  ## Users / sudo           ##
  ############################

  users.users.martin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "podman" "video" "render" ]; # Added video/render groups
    initialPassword = "changeme";
  };
  security.sudo.wheelNeedsPassword = true;
  
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

  # COSMIC from nixpkgs
  services.displayManager.cosmic-greeter.enable = true;
  services.desktopManager.cosmic.enable = true;
  services.system76-scheduler.enable = true;

  ############################
  ## Printing (Official RPM)##
  ############################

  services.printing = {
    enable = true;
    logLevel = "debug";
    drivers = [ ricohDriver ]; 
  };

  hardware.printers = {
    ensurePrinters = [
      {
        name = "Ricoh_SP_220Nw";
        deviceUri = "socket://10.0.5.10:9100";
        model = "ricoh/RICOH-SP-220Nw.ppd"; 
        ppdOptions = { PageSize = "A4"; };
      }
    ];
    ensureDefaultPrinter = "Ricoh_SP_220Nw";
  };

  ############################
  ## Flatpak                ##
  ############################
  
  services.flatpak.enable = true;

  ############################
  ## Containers (Podman)    ##
  ############################

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  ############################
  ## Audio (PipeWire)       ##
  ############################

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  ############################
  ## DBus / Polkit          ##
  ############################

  services.dbus.enable = true;
  security.polkit.enable = true;

  ############################
  ## Dev / Desktop packages ##
  ############################

  environment.systemPackages = with pkgs; [
    # Core System Utils
    git
    curl
    wget
    htop
    btop
    unzip
    zip
    file
    pciutils # Added for lspci diagnostics
    
    # Wayland/DE Utils
    libsForQt5.qt5.qtwayland
    qt6.qtwayland
    
    # Cosmic Apps
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

    # Podman/Docker
    podman
    podman-tui
    docker-compose
  ];

  # Keep Avahi for network discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      userServices = true;
    };
  };

  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  system.stateVersion = "25.11";
}