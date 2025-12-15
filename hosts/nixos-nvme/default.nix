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

    # Enable systemd in initrd (Required for TPM2/FIDO2 unlocking)
    initrd.systemd.enable = true;

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

    # REQUIRED: Smart Card Daemon for YubiKey
    pcscd.enable = true;
    
    # REQUIRED: Udev rules for hardware tokens
    udev.packages = [ 
        pkgs.yubikey-personalization 
        # Added libfido2 here so the Kensington Key is detected as a user device
        pkgs.libfido2
    ];

    # --- BIOMETRICS (Fingerprint via FIDO2) ---
    # The Kensington VeriMark is a FIDO2 device, not a standard 'fprint' device.
    # So I am disabling fprintd and using pam_u2f (configured below in 'security').
    fprintd.enable = false; 

    # Face ID (Webcam) - Optional: Can conflict with fingerprint if not careful
    # howdy = {
    #   enable = true;
    #   settings = {
    #     core = { no_confirmation = true; };
    #     video = { device_path = "/dev/video0"; }; # Check your camera path!
    #   };
    # };
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
  ## SECRETS (SOPS)         ##
  ############################

sops = {
  defaultSopsFile = ./secrets.yaml;
  defaultSopsFormat = "yaml";
  age.keyFile = "/home/martin/.config/sops/age/keys.txt";

  # --- FIX: Bundle BOTH tools with the YubiKey plugin ---
  package = pkgs.runCommand "sops-with-plugins" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  } ''
    mkdir -p $out/bin

    # 1. Wrap 'sops' (for your manual use)
    makeWrapper ${pkgs.sops}/bin/sops $out/bin/sops \
      --prefix PATH : "${pkgs.age-plugin-yubikey}/bin"

    # 2. Wrap 'sops-install-secrets' (for the system boot/test)
    # We pull this from the 'inputs' you have at the top of the file
    makeWrapper ${inputs.sops-nix.packages.${pkgs.system}.sops-install-secrets}/bin/sops-install-secrets $out/bin/sops-install-secrets \
      --prefix PATH : "${pkgs.age-plugin-yubikey}/bin"
  '';
  # ------------------------------------------------------

  secrets.martin_password = {
    neededForUsers = true;
  };
};

  ############################
  ## Users / sudo           ##
  ############################

  users.users.root = {
    initialPassword = "backup-root-password";
  };

  users.users.martin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "podman" "video" "render" ];
    
    # --- SECURE PASSWORD (Replacing 'changeme') ---
    hashedPasswordFile = config.sops.secrets.martin_password.path;
  };
   
  security = {
    sudo.wheelNeedsPassword = true;
    rtkit.enable = true;
    polkit.enable = true;
    
    # --- PAM / BIOMETRICS (Via U2F/FIDO2) ---
    # This enables using the Kensington Key (and YubiKey) for sudo/login.
    # Note: I still need to run 'pamu2fcfg > ~/.config/Yubico/u2f_keys' to associate it.
    pam.u2f = {
        enable = true;
        # control = "sufficient"; # Default is sufficient (password OR key works)
        cue = true; # Shows a message "Touch Device" when prompted
    };

    # Commented out fprintAuth because Kensington is U2F, not fprintd.
    # pam.services = {
    #   login.fprintAuth = true;
    #   xscreensaver.fprintAuth = true;
    #   cosmic-greeter.fprintAuth = true; # Login Screen
    #   sudo.fprintAuth = true;           # Sudo with finger
    # };
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
    
    # Secret Management Tools (System-wide)
    sops
    age
    age-plugin-yubikey

    # Hardware Token Tools (Kensington/YubiKey)
    libfido2     # needed for 'fido2-token' to manage the Kensington
    pam_u2f      # needed for 'pamu2fcfg' to generate auth files
  ];

  system.stateVersion = "25.11";
}
