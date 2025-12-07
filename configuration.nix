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

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 8;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos-nvme";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Dublin";
  i18n.defaultLocale = "en_IE.UTF-8";
  console.keyMap = "us";

  ############################
  ## Graphics / Wayland     ##
  ############################

  hardware.opengl.enable = true;
  hardware.opengl.driSupport32Bit = true;

  programs.xwayland.enable = true;

  ############################
  ## Memory / swap          ##
  ############################

  # zram + your existing swap LV
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
    initialPassword = "changeme"; # only used on first creation
  };

  security.sudo.wheelNeedsPassword = true;

  ############################
  ## Wayland: Hyprland/Niri ##
  ############################

  # No X11 desktop, pure Wayland
  services.xserver.enable = false;

  programs.hyprland.enable = true;
  programs.niri.enable = true;

  # greetd + tuigreet, default into Hyprland
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

  environment.systemPackages = with pkgs; [
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
    gemini-cli   # Google Gemini
    claude-code  # Anthropic Claude
    copilot-cli  # GitHub Copilot CLI
    awscli2      # AWS CLI v2
    llm          # generic LLM CLI
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
