{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.my.desktop;
in
{
  options.my.desktop = {
    enable = lib.mkEnableOption "Desktop Environment (Cosmic)";
    gnome.enable = lib.mkEnableOption "Desktop Environment (GNOME 50)";
    lite.enable = lib.mkEnableOption "Lite Desktop (Sway)";
  };

  imports = [ ];

  config = lib.mkMerge [
    # ==========================================
    # DESKTOP (COSMIC)
    # ==========================================
    (lib.mkIf cfg.enable {
      services = {
        displayManager.cosmic-greeter.enable = lib.mkDefault true;
        desktopManager.cosmic.enable = true;
        system76-scheduler.enable = true;
      };

      xdg.portal = {
        extraPortals = [ pkgs.xdg-desktop-portal-cosmic ];
        config.common.default = "cosmic";
      };

      environment.systemPackages = with pkgs; [
        cosmic-files
        cosmic-term
        cosmic-edit
        cosmic-screenshot
        cosmic-randr
      ];
    })

    # ==========================================
    # DESKTOP (GNOME 50)
    # ==========================================
    (lib.mkIf cfg.gnome.enable {
      services = {
        displayManager.gdm = {
          enable = true;
        };
        desktopManager.gnome.enable = true;

        # If GNOME is enabled, GDM takes precedence over cosmic-greeter
        displayManager.cosmic-greeter.enable = lib.mkForce false;
      };

      # GNOME specific optimizations
      services.gnome = {
        core-apps.enable = true;
        gnome-keyring.enable = true;
      };

      # Disable GDM smartcard login to show normal user list when YubiKey is plugged in
      programs.dconf.profiles.gdm = {
        databases = [
          {
            settings = {
              "org/gnome/login-screen" = {
                "enable-smartcard-authentication" = false;
              };
            };
          }
        ];
      };

      # The host should use the containerized CUPS via CUPS_SERVER env var.
      # Enabling it here causes a conflict on port 631 and shadows the container.
      services.printing.enable = false;

      xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gnome ];

      # Exclude legacy or redundant default apps
      environment.gnome.excludePackages = with pkgs; [
        gnome-tour
        epiphany # Gnome Web
        geary # Email
        gnome-characters # Replaced by smile
        totem # Replaced by showtime
        gnome-music # Replaced by amberol
      ];

      environment.systemPackages = with pkgs; [
        # GNOME Tweaks & Tools
        gnome-tweaks
        dconf-editor
        gnome-extension-manager

        # Premium Extensions for GNOME 50
        gnomeExtensions.blur-my-shell
        gnomeExtensions.dash-to-dock
        gnomeExtensions.appindicator
        gnomeExtensions.just-perfection
        gnomeExtensions.vitals
        gnomeExtensions.caffeine
        gnomeExtensions.clipboard-indicator
        gnomeExtensions.gsconnect
        gnomeExtensions.space-bar
        gnomeExtensions.search-light
        gnomeExtensions.removable-drive-menu
        gnomeExtensions.tiling-assistant
        gnomeExtensions.logo-menu

        # Modern GNOME Apps & Utilities (Premium Suite)
        ptyxis # Container-aware terminal
        gnome-text-editor
        loupe # Image Viewer
        showtime # Modern Video Player (Successor to Totem)
        amberol # Beautiful, minimal Music Player
        papers # Modern Document/PDF Viewer (Successor to Evince)
        mission-center # Advanced System Monitoring (Pro Task Manager)
        fragments # Elegant BitTorrent client
        snapshot # Camera
        baobab # Disk Usage
        gnome-disk-utility
        gnome-system-monitor
        gnome-calculator
        gnome-calendar
        gnome-weather
        gnome-clocks
        gnome-font-viewer
        gnome-logs
        smile # Modern Emoji Picker
        waypipe # Wayland remote display forwarding over SSH
      ];

      fonts.packages = with pkgs; [
        inter
        nerd-fonts.jetbrains-mono
      ];
    })

    # ==========================================
    # LITE DESKTOP (SWAY) - TUNED FOR ORIN NANO
    # ==========================================
    (lib.mkIf cfg.lite.enable {
      programs.sway = {
        enable = true;
        wrapperFeatures.gtk = true;
        extraSessionCommands = ''
          # NVIDIA / JetPack Wayland Compatibility
          export WLR_NO_HARDWARE_CURSORS=1
          export WLR_RENDERER=vulkan
          export __GL_GSYNC_ALLOWED=0
          export __GL_VRR_ALLOWED=0
          # Fix for Java apps
          export _JAVA_AWT_WM_NONREPARENTING=1
        '';
        extraPackages = with pkgs; [
          swaylock-effects # Prettier lockscreen
          swayidle
          foot # Minimal fast terminal
          wofi # Premium launcher
          waybar # Glassmorphism status bar
          mako # Notification daemon
          grim # Screenshot
          slurp # Select region
          wl-clipboard
          kanshi # Display management
          swaybg # Wallpaper support
          waypipe # Wayland remote display forwarding over SSH
        ];
      };

      # Force Wayland for Chromium/Electron
      environment.sessionVariables.NIXOS_OZONE_WL = "1";

      # Use a minimal but modern greeter
      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd 'sway --unsupported-gpu'";
            user = "greeter";
          };
        };
      };

      # Standard font for the UI
      fonts.packages = with pkgs; [
        inter
        nerd-fonts.jetbrains-mono
      ];
    })

    # ==========================================
    # COMMON DESKTOP CONFIGURATION
    # ==========================================
    (lib.mkIf (cfg.enable || cfg.gnome.enable || cfg.lite.enable) {
      boot.plymouth = {
        enable = true;
        theme = "bgrt";
      };

      services = {
        power-profiles-daemon.enable = true;
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
      };

      hardware.graphics.enable = true;

      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      };

      programs = {
        dconf.enable = true;
        weylus = {
          enable = true;
          openFirewall = true;
          users = [ config.my.username ];
        };
        xwayland.enable = true;
      };

      # System-wide Default Browser
      xdg.mime.defaultApplications = {
        "text/html" = "firefox-standard.desktop";
        "x-scheme-handler/http" = "firefox-standard.desktop";
        "x-scheme-handler/https" = "firefox-standard.desktop";
        "x-scheme-handler/about" = "firefox-standard.desktop";
        "x-scheme-handler/unknown" = "firefox-standard.desktop";
      };

      environment = {
        sessionVariables.NIXOS_OZONE_WL = "1";

        etc."chromium/policies/managed/lab_policies.json".text = builtins.toJSON {
          ClearSiteDataOnExit = false;
          BlockThirdPartyCookies = false;
          SignInAllowed = false;
          DeveloperToolsAvailability = 1;
          MetricsReportingEnabled = false;
          SpellCheckServiceEnabled = false;
          ExtensionSettings = {
            "cjpalhdlnbpafiamejdnhcphjbkeiagm" = {
              installation_mode = "force_installed";
              update_url = "https://clients2.google.com/service/update2/crx";
            };
          };
          PasswordManagerEnabled = false;
          AutofillAddressEnabled = false;
          AutofillCreditCardEnabled = false;
        };

        systemPackages = with pkgs; [
          libsForQt5.qt5.qtwayland
          qt6.qtwayland
          nyxt
          zoom-us
          bleachbit
          just
        ];
      };

      fonts.fontconfig.enable = true;
    })
  ];
}
