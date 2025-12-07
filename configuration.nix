{ config, pkgs, ... }:

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

  # Use the latest kernel for 13th Gen Intel support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 8;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- SILENCE & FIXES ---
  
  # 1. Kill the PC Speaker driver to prevent "screaming" on error
  boot.blacklistedKernelModules = [ "pcspkr" "snd_pcsp" ];
  
  # 2. Force silent boot (hides Zotac BIOS errors)
  boot.consoleLogLevel = 0; 
  
  boot.kernelParams = [
    "quiet"                     # Force kernel silence
    "loglevel=0"                # Only show Emergency errors
    "udev.log_level=3"          
    "acpi_osi=Linux"            # Zotac ACPI Fix
    "intel_idle.max_cstate=1"   # Zotac Freeze Fix
    "i915.enable_psr=0"         # Screen Flicker Fix
    
    # Audio Fix: Prevent audio card sleep (stops popping/screaming loops)
    "snd_hda_intel.power_save=0"
    "snd_hda_intel.power_save_controller=N"
  ];

  networking.hostName = "nixos-nvme";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Dublin";
  i18n.defaultLocale = "en_IE.UTF-8";
  console.keyMap = "us";

  ############################
  ## Hardware / Firmware    ##
  ############################

  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableAllFirmware = true;

  ############################
  ## Graphics / Wayland     ##
  ############################

  # /etc/nixos/configuration.nix

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    
    # Drivers for Intel UHD Graphics (13th Gen/Raptor Lake)
    extraPackages = with pkgs; [
      intel-media-driver   # LIBVA_DRIVER_NAME=iHD (Crucial for hardware accel)
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  # Force Intel to use the correct driver backend
  environment.sessionVariables = { 
    LIBVA_DRIVER_NAME = "iHD"; 
  };

  programs.xwayland.enable = true;

  ############################
  ## Memory / swap          ##
  ############################

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
  };

  ############################
  ## Users / sudo           ##
  ############################

  users.users.martin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "podman" ];
    initialPassword = "changeme";
  };
  security.sudo.wheelNeedsPassword = true;

  # Autostart the Polkit Agent for GUI apps (Password popups)
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

  ############################
  ## Wayland: Hyprland/Niri ##
  ############################

  services.xserver.enable = false;
  programs.hyprland.enable = true;
  programs.niri.enable = true;

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
      user = "greeter";
    };
  };

  ############################
  ## Flatpak / portals      ##
  ############################

  services.flatpak.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs;
    [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-hyprland
    ];
  };

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

  hardware.pulseaudio.enable = false;
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
  ## Filesystems / tmpfs    ##
  ############################

  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType  = "tmpfs";
    options = [ "mode=1777" "nodev" "nosuid" "noexec" ];
  };

  ############################
  ## Dev / Desktop packages ##
  ############################

  environment.systemPackages = with pkgs;
  [
    # Browser
    google-chrome

    # Wayland / desktop bits
    kitty
    alacritty
    waybar
    wofi
    fuzzel
    swaybg
    grim
    slurp
    wl-clipboard
    tuigreet

    # Desktop Plumbing (Must have)
    xfce.thunar          
    pavucontrol          
    networkmanagerapplet 
    blueman              
    libnotify            
    swaynotificationcenter 
    polkit_gnome         
    hyprlock             
    hypridle             
    hyprpaper            
    libsForQt5.qt5.qtwayland 
    qt6.qtwayland            

    # Dev / CLI tools
    git
    just
    jq
    curl
    wget
    htop
    btop
    ripgrep
    fd
    neovim
    tree
    unzip
    zip
    file
    vscode-fhs

    # Nix / DX
    direnv
    nix-direnv
    home-manager
    nixfmt-rfc-style
    nil

    # Containers
    podman
    podman-tui
    docker-compose

    # AI CLIs
    gemini-cli
    claude-code
    copilot-cli
    awscli2
    llm

    nwg-look
  ];

  ############################
  ## Direnv integration     ##
  ############################

  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  ############################
  ## System version         ##
  ############################

  system.stateVersion = "25.11";
}