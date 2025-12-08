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

      substituters = [
        "https://cache.nixos.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:Ik/ZBziETSRre3nCpv7l4WwhDD5OhoOx9LG/mIJV6Hg="
      ];
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
    ];
  };

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

  # COSMIC from nixpkgs
  services.displayManager.cosmic-greeter.enable = true;
  services.desktopManager.cosmic.enable = true;

  # Optional: System76 scheduler (COSMIC docs recommend this)
  services.system76-scheduler.enable = true;

  ############################
  ## Flatpak / portals      ##
  ############################

  services.flatpak.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
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
  ## DBus / Polkit / FS     ##
  ############################

  services.dbus.enable = true;
  security.polkit.enable = true;

  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=1777" "nodev" "nosuid" "noexec" ];
  };

  ############################
  ## Dev / Desktop packages ##
  ############################

  environment.systemPackages = with pkgs; [
    google-chrome
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

    direnv
    nix-direnv
    home-manager
    nixfmt-rfc-style
    nil

    podman
    podman-tui
    docker-compose

    gemini-cli
    claude-code
    copilot-cli
    awscli2
    llm

    nwg-look
  ];

  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  system.stateVersion = "25.11";
}
