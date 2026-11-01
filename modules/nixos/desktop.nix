{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.my.desktop;

  # mat2's test_all_parametred has an ffmpeg-version-dependent assertion that
  # flakes; skip just that test.
  metadata-cleaner-fixed = pkgs.metadata-cleaner.overrideAttrs (old: {
    # `dependencies` becomes propagatedBuildInputs before mkDerivation, so
    # that's the attribute to patch.
    propagatedBuildInputs = map (
      dep:
      if (dep.pname or null) == "mat2" then
        dep.overridePythonAttrs (o: {
          disabledTests = (o.disabledTests or [ ]) ++ [ "test_all_parametred" ];
        })
      else
        dep
    ) old.propagatedBuildInputs;
  });
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
      # Insecure re-acks, gated to desktop hosts. electron: bitwarden-desktop's
      # pinned Electron. firefox-esr-140: Zotero's runtime; drop when Zotero 11
      # moves to ESR 153.
      nixpkgs.config.allowInsecurePredicate =
        pkg:
        builtins.elem (lib.getName pkg) [
          "electron"
          "firefox-esr-140-bin-unwrapped"
        ];

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
        gnome-remote-desktop.enable = true;
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

        # GNOME extensions: stock top bar and overview plus dash-to-dock. Check
        # an extension supports the current shell version before adding it
        # (search-light and media-controls are out until they support Shell 50;
        # weather-oclock can't resolve our location).
        # Enable/dconf settings live in modules/home-manager/gnome.nix.
        gnomeExtensions.blur-my-shell
        gnomeExtensions.dash-to-dock # Fast autohide bottom dock
        gnomeExtensions.arcmenu # Top-bar app menu (search, categories, pinned/recent apps)
        gnomeExtensions.appindicator
        gnomeExtensions.just-perfection
        gnomeExtensions.vitals
        gnomeExtensions.caffeine
        gnomeExtensions.clipboard-indicator # Clipboard manager
        gnomeExtensions.gsconnect
        gnomeExtensions.space-bar
        gnomeExtensions.removable-drive-menu
        gnomeExtensions.tiling-assistant
        gnomeExtensions.custom-command-list # Top-bar shortcuts to `just` recipes
        gnomeExtensions.bluetooth-quick-connect # Connect paired BT devices from Quick Settings
        gnomeExtensions.quick-settings-audio-panel # Per-app volume + output switcher in QS
        gnomeExtensions.rounded-window-corners-reborn # Completes the blur-my-shell aesthetic
        gnomeExtensions.top-panel-notification-icons-w-count # Individual app icons with unread badges in top panel
        gnomeExtensions.notification-banner-re-reloaded # Anchor notification banners to top-right corner
        gnomeExtensions.notification-timeout # Configurable auto-dismiss timeout for notification banners
        gnomeExtensions.brightness-control-using-ddcutil # Per-monitor brightness slider in Quick Settings via DDC/CI

        # Modern GNOME Apps & Utilities (Premium Suite)
        ptyxis # Container-aware terminal
        gnome-text-editor
        loupe # Image Viewer
        showtime # Modern Video Player (Successor to Totem)
        amberol # Beautiful, minimal Music Player
        papers # Modern Document/PDF Viewer (Successor to Evince)
        kdePackages.okular # PDF annotation/form-filling (native Wayland, KDE)
        mission-center # Advanced System Monitoring (Pro Task Manager)
        newsflash # Modern feed reader (GTK4 / Libadwaita)
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

        # Utilities (homelab / privacy / imaging)
        impression # GUI USB/SD image writer (Orin/OpenWrt installer flashing)
        metadata-cleaner-fixed # Strip EXIF/metadata before sharing (privacy)
        switcheroo # Batch image format/resize converter (GTK4)
        dialect # Translation front-end (self-hostable backend)
        eyedropper # Color picker / palette builder

        # Screenshot annotation. Satty needs an input image; wire a GNOME
        # Wayland region-capture → satty pipeline (bound to <Super><Shift>s
        # in home-manager gnome.nix). Uses the GNOME Shell Screenshot D-Bus
        # API, which works under Wayland where grim/slurp do not.
        satty
        (writeShellApplication {
          name = "satty-screenshot";
          runtimeInputs = [
            glib # gdbus
            coreutils # mktemp, tr
            satty
            wl-clipboard # wl-copy for --copy-command
          ];
          text = ''
            tmp=$(mktemp --suffix=.png)
            trap 'rm -f "$tmp"' EXIT
            read -r x y w h < <(
              gdbus call --session \
                --dest org.gnome.Shell.Screenshot \
                --object-path /org/gnome/Shell/Screenshot \
                --method org.gnome.Shell.Screenshot.SelectArea \
                | tr -d '(),'
            )
            gdbus call --session \
              --dest org.gnome.Shell.Screenshot \
              --object-path /org/gnome/Shell/Screenshot \
              --method org.gnome.Shell.Screenshot.ScreenshotArea \
              "$x" "$y" "$w" "$h" false "$tmp" >/dev/null
            satty --filename "$tmp" --copy-command wl-copy --early-exit
          '';
        })

        # Password Management
        # Plain package, not firejail-wrapped: its polkit policy (biometric
        # unlock) and desktop_proxy bridge (Chrome extension link) must land
        # in the system profile.
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

      hardware = {
        graphics.enable = true;
        bluetooth = {
          enable = true;
          powerOnBoot = true;
          settings = {
            General = {
              AutoEnable = "true";
            };
          };
        };
      };

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
        "text/html" = "google-chrome-stable.desktop";
        "x-scheme-handler/http" = "google-chrome-stable.desktop";
        "x-scheme-handler/https" = "google-chrome-stable.desktop";
        "x-scheme-handler/about" = "google-chrome-stable.desktop";
        "x-scheme-handler/unknown" = "google-chrome-stable.desktop";
      };

      environment = {
        # Chrome stays unmanaged (no policies/managed/): a managed policy
        # disables sign-in, sync and GenAI features. Browser flags live in
        # commandLineArgs (nix-presets/desktop.nix); install uBlock Origin by hand.
        sessionVariables.NIXOS_OZONE_WL = "1";

        systemPackages = with pkgs; [
          qt5.qtwayland
          qt6.qtwayland
          bleachbit
          just
        ];
      };

      fonts.fontconfig.enable = true;
    })
  ];
}
