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
    gnome.enable = lib.mkEnableOption "Desktop Environment (GNOME 50)";
  };

  imports = [ ];

  config = lib.mkMerge [
    # ==========================================
    # DESKTOP (GNOME 50)
    # ==========================================
    (lib.mkIf cfg.gnome.enable {
      # Per-version insecure re-ack, co-located with its consumer and gated to
      # the desktop host (never blanket host-level — see modules/flake/hosts.nix).
      # bitwarden-desktop pins electron_39; when it bumps, eval trips here and
      # forces a conscious re-ack rather than silently carrying an old Electron.
      nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];

      services = {
        displayManager.gdm = {
          enable = true;
        };
        desktopManager.gnome.enable = true;
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
                "disable-user-list" = false;
              };
            };
          }
        ];
      };

      # Enable local CUPS daemon to act as a proxy/client for GUI applications like Chrome
      services.printing = {
        enable = true;
      };

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
        gnomeExtensions.dash-to-panel
        gnomeExtensions.dash-to-dock # installed but disabled — toggle via gnome-extensions-app
        gnomeExtensions.arcmenu
        gnomeExtensions.desktop-icons-ng-ding
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
        gnomeExtensions.pano # Rich clipboard manager (replaces clipboard-indicator)
        gnomeExtensions.user-themes
        gnomeExtensions.quick-settings-tweaker
        gnomeExtensions.custom-command-list # Top-bar shortcuts to `just` recipes

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

        # Password Management
        # Installed as a plain package (NOT firejail-wrapped): the launcher,
        # app-grid entry, icons, the biometric-unlock polkit policy
        # (share/polkit-1/actions/com.bitwarden.Bitwarden.policy) and the
        # libexec/desktop_proxy native-messaging bridge all need to land in the
        # system profile. Firefox integration is wired in nix-presets/firefox.nix.
        bitwarden-desktop
      ];

      fonts.packages = with pkgs; [
        inter
        nerd-fonts.jetbrains-mono
      ];
    })

    # ==========================================
    # COMMON DESKTOP CONFIGURATION
    # ==========================================
    (lib.mkIf cfg.gnome.enable {
      boot.plymouth = {
        enable = true;
        theme = "bgrt";
      };

      services = {
        power-profiles-daemon.enable = true;
        flatpak = {
          enable = true;
        };
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
          qt5.qtwayland
          qt6.qtwayland
          nyxt
          bleachbit
          just
        ];
      };

      fonts.fontconfig.enable = true;
    })
  ];
}
