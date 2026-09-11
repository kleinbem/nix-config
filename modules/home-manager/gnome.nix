{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.modules.gnome = {
    enable = lib.mkEnableOption "GNOME configuration";
  };

  config = lib.mkIf config.modules.gnome.enable {
    # KDE Frameworks apps (Okular, etc) don't follow the GTK3 Qt-platform
    # bridge in nix-presets/desktop.nix — they read their own kdeglobals
    # color scheme instead, independent of QT_QPA_PLATFORMTHEME.
    qt.style = {
      name = "breeze";
      package = pkgs.kdePackages.breeze;
    };

    # Rofi app launcher, bound to <Super>r below. GNOME's Mutter doesn't
    # implement the zwlr_layer_shell_v1 Wayland protocol (same protocol gap
    # as the bitwarden.desktop clipboard workaround below), so rofi's native
    # Wayland backend hard-aborts with "requires support for the layer shell
    # protocol". Wrap the binary to unset WAYLAND_DISPLAY, forcing rofi onto
    # its working xcb/XWayland backend (programs.xwayland.enable = true in
    # nixos/desktop.nix) — confirmed live, this is not a compile-time toggle.
    programs.rofi = {
      enable = true;
      package = pkgs.symlinkJoin {
        name = "rofi-xwayland-wrapped";
        paths = [ pkgs.rofi ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/rofi --unset WAYLAND_DISPLAY
        '';
      };
      terminal = "${pkgs.ptyxis}/bin/ptyxis";
      extraConfig = {
        modi = "drun,run,window";
        show-icons = true;
        display-drun = "Apps";
        display-run = "Run";
        display-window = "Windows";
        drun-display-format = "{name}";
      };
      theme =
        let
          inherit (config.lib.formats.rasi) mkLiteral;
        in
        {
          "*" = {
            bg = mkLiteral "#1e1e2e";
            bg-alt = mkLiteral "#313244";
            fg = mkLiteral "#cdd6f4";
            accent = mkLiteral "#89b4fa";
          };
          window = {
            background-color = mkLiteral "@bg";
            border = mkLiteral "1px";
            border-color = mkLiteral "@accent";
            border-radius = mkLiteral "8px";
            width = mkLiteral "600px";
          };
          inputbar = {
            background-color = mkLiteral "@bg-alt";
            text-color = mkLiteral "@fg";
            padding = mkLiteral "10px";
            border-radius = mkLiteral "6px";
            margin = mkLiteral "10px";
          };
          listview = {
            background-color = mkLiteral "@bg";
            margin = mkLiteral "10px";
          };
          element = {
            padding = mkLiteral "6px";
            text-color = mkLiteral "@fg";
          };
          "element selected" = {
            background-color = mkLiteral "@accent";
            text-color = mkLiteral "@bg";
            border-radius = mkLiteral "6px";
          };
        };
    };

    xdg.configFile."kdeglobals".text = ''
      [General]
      ColorScheme=BreezeDark

      [KDE]
      LookAndFeelPackage=org.kde.breezedark.desktop
      widgetStyle=Breeze
    '';

    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        enable-hot-corners = true;
        show-battery-percentage = true;
        font-name = "Inter 11";
        document-font-name = "Inter 11";
        monospace-font-name = "JetBrainsMono Nerd Font 10";
        clock-show-weekday = true;
        clock-show-date = true;
        clock-show-seconds = true;
        gtk-enable-primary-paste = true;
        locate-pointer = true;
      };

      "org/gnome/desktop/calendar" = {
        show-weekdate = true;
      };

      "org/gnome/desktop/wm/preferences" = {
        button-layout = "appmenu:minimize,maximize,close";
        center-new-windows = true;
        focus-mode = "click";
        action-double-click-titlebar = "toggle-maximize";
      };

      "org/gnome/mutter" = {
        edge-tiling = true;
        dynamic-workspaces = true;
        center-new-windows = true;
        workspaces-only-on-primary = true;
        # Free left-Super from triggering the overview; it's used as a modifier
        # for workspace and clipboard shortcuts, so accidental taps are annoying.
        # Right-Super still opens the overview, and <Super>a is bound below.
        overlay-key = "Super_R";
        experimental-features = [
          "scale-monitor-framebuffer"
          "xwayland-native-scaling"
          "variable-refresh-rate"
        ];
      };

      "org/gnome/shell/keybindings" = {
        toggle-overview = [ "<Super>a" ];
        toggle-application-view = [ "<Super>grave" ];
        toggle-message-tray = [ "<Super>n" ];
      };

      "org/gnome/settings-daemon/plugins/color" = {
        night-light-enabled = true;
        night-light-schedule-automatic = true;
      };

      "org/gnome/desktop/peripherals/touchpad" = {
        tap-to-click = true;
        natural-scroll = true;
        disable-while-typing = true;
        click-method = "fingers";
      };

      "org/gnome/desktop/peripherals/mouse" = {
        accel-profile = "flat";
      };

      "org/gnome/settings-daemon/plugins/xsettings" = {
        antialiasing = "rgba";
        hinting = "slight";
      };

      "org/gnome/desktop/sound" = {
        event-sounds = false;
      };

      "org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type = "nothing";
        power-button-action = "interactive";
      };

      "org/gnome/shell" = {
        disable-user-extensions = false;
        # GNOME-native workflow: stock top bar + overview, fast-autohide bottom
        # dock (see extensions/dash-to-dock below) instead of a full bottom
        # panel. Trimmed 24 → 18 extensions on 2026-09-10. Removed:
        #   dash-to-panel  → dash-to-dock (autohide); top bar comes back natively
        #   ding           → no desktop icons
        #   logo-menu      → its launchers already exist as keybindings below
        #   user-theme     → inert, no custom shell theme is shipped
        #   quick-settings-tweaks → broadest shell patcher; media dup'd mediacontrols
        #   flypie         → search-light (<Super>space) + rofi (<Super>r) are enough
        # Removed 2026-09-11 (still installed upstream, but broken on this shell):
        #   search-light   → packaged v42 only declares shell-version 48/49
        #   mediacontrols  → packaged v47 only declares shell-version 46-49
        #   both show State: OUT OF DATE on GNOME Shell 50.4 — re-add once nixpkgs
        #   ships a version whose metadata.json lists "50".
        # Removed 2026-09-11: weatheroclock — GNOME's weather backend
        # (org/gnome/shell/weather) needs a location and location-services is
        # off system-wide; libgweather's location DB also has no entry for
        # Watergrasshill or any nearby town, only "Cork Airport" ~18km out.
        # With no location it just spun forever next to the clock. Dropped
        # rather than pinning an inexact/mislabeled location.
        # Re-added 2026-09-11: arcmenu — wanted a top-bar app menu; verified
        # shell-version 50 support (v73) before adding this time, unlike the
        # search-light/mediacontrols mistake above.
        enabled-extensions = [
          "blur-my-shell@aunetx"
          "dash-to-dock@micxgx.gmail.com"
          "arcmenu@arcmenu.com"
          "appindicatorsupport@rgcjonas.gmail.com"
          "just-perfection-desktop@just-perfection"
          "Vitals@CoreCoding.com"
          "caffeine@patapon.info"
          "clipboard-indicator@tudmotu.com"
          "gsconnect@andyholmes.github.io"
          "space-bar@luchrioh"
          "drive-menu@gnome-shell-extensions.gcampax.github.com"
          "tiling-assistant@leleat-on-github"
          "custom-command-list@storageb.github.com"
          "bluetooth-quick-connect@bjarosze.gmail.com"
          "quick-settings-audio-panel@rayzeq.github.io"
          "rounded-window-corners@fxgn"
        ];
        # Explicit empty list: GNOME writes disabled UUIDs here whenever an
        # extension errors out (or a user disables one via the Extensions app),
        # and that key isn't cleared by anything else — it silently overrides
        # enabled-extensions above and survives across home-manager switches.
        # Declaring it empty makes every switch self-heal that state instead
        # of a broken/manually-disabled extension staying stuck disabled.
        disabled-extensions = [ ];
        favorite-apps = [
          "google-chrome-stable.desktop"
          "org.gnome.Nautilus.desktop"
          "org.gnome.Ptyxis.desktop"
          "org.gnome.Software.desktop"
          "org.gnome.Console.desktop"
        ];
      };

      "org/gnome/shell/extensions/blur-my-shell" = {
        brightness = 0.6;
        sigma = 30;
        settings-version = 2;
      };

      "org/gnome/shell/extensions/blur-my-shell/appfolder" = {
        brightness = 0.6;
        sigma = 30;
      };

      "org/gnome/shell/extensions/blur-my-shell/dash-to-dock" = {
        blur = true;
        brightness = 0.6;
        sigma = 30;
        static-blur = true;
        style-dash-to-dock = 0;
      };

      "org/gnome/shell/extensions/blur-my-shell/panel" = {
        brightness = 0.6;
        sigma = 30;
        corner-radius = 0;
      };

      "org/gnome/shell/extensions/blur-my-shell/overview" = {
        blur = true;
        brightness = 0.6;
        sigma = 30;
      };

      # Dock: bottom, plain autohide (not "intelligent" — hides regardless of
      # window overlap) reserving no screen space while hidden. Tuned for a
      # fast reaction: no pressure-barrier push needed, short show/hide delays,
      # quick slide animation. hot-keys = false so Super+1..9 stay bound to
      # workspace switching (wm/keybindings below), not dock-item activation.
      "org/gnome/shell/extensions/dash-to-dock" = {
        dock-position = "BOTTOM";
        dock-fixed = false;
        autohide = true;
        intellihide = false;
        require-pressure-to-show = false;
        show-delay = 0.05;
        hide-delay = 0.1;
        animation-time = 0.1;
        autohide-in-fullscreen = false;
        extend-height = false;
        height-fraction = 0.9;
        dash-max-icon-size = 32; # Slimmer than the nixpkgs default (48/44)
        icon-size-fixed = true; # Don't let it creep back up when scrolling/scaling
        show-apps-at-top = true;
        show-show-apps-button = true;
        show-mounts = false;
        show-trash = false;
        isolate-workspaces = false;
        click-action = "minimize-or-previews";
        scroll-action = "cycle-windows";
        running-indicator-style = "DOTS";
        custom-theme-shrink = true;
        transparency-mode = "DYNAMIC";
        hot-keys = false;
      };

      # ArcMenu: centered top-bar app menu with a separate Activities button
      # (stock top bar has neither, since dash-to-dock's autohide replaced
      # dash-to-panel above) using the Pop!_OS-style "pop" menu layout.
      "org/gnome/shell/extensions/arcmenu" = {
        position-in-panel = "Center";
        show-activities-button = true;
        menu-layout = "pop";
      };

      "org/gnome/shell/extensions/just-perfection" = {
        accessibility-menu = false;
        search = true;
        animation = 1; # Fast animations
        window-demanding-attention-focus = true;
        startup-status = 1; # Startup status: Overview (GNOME-native flow)
        panel-size = 28; # Sleeker top bar height
        panel-button-padding-size = 6; # Closer top bar item spacing
      };

      "org/gnome/shell/extensions/space-bar/appearance" = {
        workspace-margin = 4;
      };

      # pano was removed from nixpkgs (upstream unmaintained, 2026-07); fall back
      # to clipboard-indicator, which is still packaged.
      "org/gnome/shell/extensions/clipboard-indicator" = {
        toggle-menu = [ "<Super>v" ];
        clear-history = [ "<Super><Shift>v" ];
        paste-on-select = true;
        notify-on-copy = false;
        history-size = 200;
        move-item-first = true;
      };

      "org/gnome/shell/extensions/tiling-assistant" = {
        enable-gradient = true;
        active-window-hint = 1; # Pulse hint
        active-window-hint-color = "rgba(53, 132, 228, 0.5)";
      };

      # Top-bar "Workspace" menu wired to common `just` recipes from the meta-flake.
      # Commands run in ptyxis and keep the pane open so output is readable.
      "org/gnome/shell/extensions/custom-command-list" =
        let
          repo = "${config.home.homeDirectory}/Develop/github.com/kleinbem/nix";
          term =
            cmd:
            "ptyxis --new-window -- bash -lc 'cd ${repo} && ${cmd}; echo; read -n1 -r -p \"Press any key to close…\"'";
        in
        {
          menutitle-setting = "Workspace";
          menuicon-setting = "applications-system-symbolic";
          menulocation-setting = 1; # Right side of top bar
          refresh-enabled-setting = true;
          command1 = lib.hm.gvariant.mkTuple [
            "Apply (full)"
            (term "just apply")
            "system-software-update-symbolic"
            true
          ];
          command2 = lib.hm.gvariant.mkTuple [
            "Apply (fast)"
            (term "just apply-fast")
            "media-playback-start-symbolic"
            true
          ];
          command3 = lib.hm.gvariant.mkTuple [
            "Status"
            (term "just status")
            "view-list-symbolic"
            true
          ];
          command4 = lib.hm.gvariant.mkTuple [
            "Health Check"
            (term "just maintenance::health-check")
            "emblem-ok-symbolic"
            true
          ];
          command5 = lib.hm.gvariant.mkTuple [
            "Clean (GC)"
            (term "just maintenance::clean")
            "user-trash-symbolic"
            true
          ];
          command6 = lib.hm.gvariant.mkTuple [
            "Deploy Fleet"
            (term "just deployment::fleet")
            "network-server-symbolic"
            true
          ];
          command7 = lib.hm.gvariant.mkTuple [
            "NetBird Status"
            (term "netbird status --detail")
            "network-vpn-symbolic"
            true
          ];
        };

      "org/gnome/shell/extensions/vitals" = {
        hot-sensors = [
          "_processor_usage_"
          "_memory_usage_"
          "_temperature_"
        ];
        show-cpu = true;
        show-memory = true;
        show-temperature = true;
        show-battery = false;
        show-storage = false;
        show-network = false;
        update-time = 2;
      };

      # --- Bluefin-inspired Improvements ---
      "org/gnome/desktop/input-sources" = {
        sources = [
          (lib.hm.gvariant.mkTuple [
            "xkb"
            "gb"
          ])
        ];
        current = lib.hm.gvariant.mkUint32 0;
      };

      "org/gnome/desktop/app-folders" = {
        folder-children = [
          "Virtualization"
          "Development"
          "Productivity"
          "Utilities"
          "FleetServices"
          "Media"
        ];
      };

      # Renamed from "Containers" (2026-09-11): virt-manager (Categories:
      # System;Emulator) and Connections (Categories: ...RemoteAccess;Network)
      # checked out as VM/remote-access tools, not "Development" or
      # "Productivity" — they sit closer to BoxBuddy/Pods than to code.desktop
      # or Papers/SimpleScan. No shared category narrow enough to auto-match
      # all four (BoxBuddy is bare "Utility"), so still hand-listed.
      "org/gnome/desktop/app-folders/folders/Virtualization" = {
        name = "Virtualization";
        apps = [
          "io.github.dvlv.boxbuddyrs.desktop"
          "com.github.marhkb.Pods.desktop"
          "virt-manager.desktop"
          "org.gnome.Connections.desktop"
        ];
      };

      # category-driven (2026-09-11): code.desktop already declares
      # Categories=Utility;TextEditor;Development;IDE — "IDE" is narrow enough
      # that nothing else installed matches it (Pods has "Development" too,
      # which would've pulled it in), so this now auto-grows for any future
      # IDE instead of needing a hand-added entry each time.
      "org/gnome/desktop/app-folders/folders/Development" = {
        name = "Development";
        categories = [ "IDE" ];
      };

      "org/gnome/desktop/app-folders/folders/Productivity" = {
        name = "Productivity";
        apps = [
          "org.gnome.Papers.desktop"
          "org.gnome.SimpleScan.desktop"
        ];
      };

      "org/gnome/desktop/app-folders/folders/Utilities" = {
        name = "Utilities";
        categories = [ "X-GNOME-Utilities" ];
        # GNOME's factory app-folders default seeds this folder's own "apps"
        # list (Decibels, Connections, Papers, font-viewer, Loupe — found live
        # in dconf, never written by this file). folder-children ordering
        # means Utilities is matched before Media below, so that stale list
        # was silently stealing apps (e.g. Decibels) from Media's AudioVideo
        # category match. Declare empty to override it, same self-healing
        # pattern as disabled-extensions above.
        apps = [ ];
      };

      # Category-driven folders (2026-09-11): rather than hand-listing apps,
      # match on freedesktop Categories. Only using categories narrow enough
      # to stay meaningful — "Utility" and "Graphics" are far too promiscuous
      # (most GNOME apps carry Utility as a secondary tag) and would swallow
      # half the grid, including apps already pinned to the dock.
      "org/gnome/desktop/app-folders/folders/FleetServices" = {
        name = "Fleet Services";
        categories = [ "WebBrowser" ];
        # The ~30 self-hosted service PWA launchers (Attic, Authelia, Frigate,
        # Home Assistant, n8n, Netdata, Paperless, Qdrant, Syncthing, etc.)
        # all declare Categories=Network;WebBrowser. Exclude the actual
        # browsers so Chrome doesn't get folded in alongside them.
        excluded-apps = [
          "google-chrome-stable.desktop"
          "google-chrome.desktop"
          "com.google.Chrome.desktop"
          "chromium-pentest.desktop"
        ];
      };

      "org/gnome/desktop/app-folders/folders/Media" = {
        name = "Media";
        categories = [ "AudioVideo" ]; # mpv, Amberol, Decibels, Showtime, Snapshot
      };

      "org/gnome/desktop/privacy" = {
        report-technical-problems = false;
        remove-old-trash-files = true;
        remove-old-temp-files = true;
        old-files-age = lib.hm.gvariant.mkUint32 30;
      };

      # --- Desktop & Workspace Keybindings ---
      "org/gnome/desktop/wm/keybindings" = {
        close = [
          "<Super>q"
          "<Alt>F4"
        ];
        minimize = [ "<Super>comma" ];
        maximize = [ "<Super>m" ];
        toggle-maximized = [ "<Super>f" ];

        # Workspace navigation (Sway-like)
        switch-to-workspace-1 = [ "<Super>1" ];
        switch-to-workspace-2 = [ "<Super>2" ];
        switch-to-workspace-3 = [ "<Super>3" ];
        switch-to-workspace-4 = [ "<Super>4" ];
        switch-to-workspace-5 = [ "<Super>5" ];
        switch-to-workspace-6 = [ "<Super>6" ];
        switch-to-workspace-7 = [ "<Super>7" ];
        switch-to-workspace-8 = [ "<Super>8" ];
        switch-to-workspace-9 = [ "<Super>9" ];

        move-to-workspace-1 = [ "<Super><Shift>1" ];
        move-to-workspace-2 = [ "<Super><Shift>2" ];
        move-to-workspace-3 = [ "<Super><Shift>3" ];
        move-to-workspace-4 = [ "<Super><Shift>4" ];
        move-to-workspace-5 = [ "<Super><Shift>5" ];
        move-to-workspace-6 = [ "<Super><Shift>6" ];
        move-to-workspace-7 = [ "<Super><Shift>7" ];
        move-to-workspace-8 = [ "<Super><Shift>8" ];
        move-to-workspace-9 = [ "<Super><Shift>9" ];
      };

      # --- Productivity Keybindings ---
      "org/gnome/settings-daemon/plugins/media-keys" = {
        custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-terminal/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-terminal-alt/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-mission-center/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-smile/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-smile-alt/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-satty/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-rofi/"
        ];
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-rofi" = {
        binding = "<Super>r";
        command = "rofi -show drun";
        name = "App Launcher (Rofi)";
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-satty" = {
        binding = "<Super><Shift>s";
        command = "satty-screenshot";
        name = "Screenshot + annotate (Satty)";
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-terminal" = {
        binding = "<Control><Alt>t";
        command = "ptyxis";
        name = "Terminal";
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-terminal-alt" = {
        binding = "<Control><Alt>Return";
        command = "ptyxis";
        name = "Terminal Alt";
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-mission-center" = {
        binding = "<Control><Shift>Escape";
        command = "missioncenter";
        name = "Mission Center";
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-smile" = {
        binding = "<Control><Alt>space";
        command = "smile";
        name = "Open up the emoji picker";
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-smile-alt" = {
        binding = "<Super>period";
        command = "smile";
        name = "Open up the emoji picker (Alt)";
      };
    };

    # GNOME's Mutter doesn't implement the zwlr_data_control_manager_v1 Wayland
    # protocol, so bitwarden-desktop's clipboard.write silently fails and its
    # X11 fallback then times out (github.com/bitwarden/clients/issues/13431).
    # Shadow nixpkgs' bitwarden.desktop (same filename wins via the higher-
    # priority ~/.local/share/applications) and drop NIXOS_OZONE_WL just for
    # this launch, forcing Bitwarden onto its working plain-X11/XWayland path.
    xdg.desktopEntries.bitwarden = {
      name = "Bitwarden";
      comment = pkgs.bitwarden-desktop.meta.description;
      exec = "env -u NIXOS_OZONE_WL bitwarden %U";
      icon = "bitwarden";
      categories = [ "Utility" ];
      mimeType = [ "x-scheme-handler/bitwarden" ];
    };
  };
}
