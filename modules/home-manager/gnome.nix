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

    # Rofi on <Super>r. Mutter lacks zwlr_layer_shell_v1, so rofi's Wayland
    # backend aborts; unsetting WAYLAND_DISPLAY puts it on XWayland.
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
      settings = {
        terminal = "${pkgs.ptyxis}/bin/ptyxis";
        modi = "drun,run,window";
        show-icons = true;
        display-drun = "Apps";
        display-run = "Run";
        display-window = "Windows";
        drun-display-format = "{name}";
      };
      # Catppuccin Mocha by hand (no rofi theme package), matching the
      # system theme in nix-presets/desktop.nix.
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
      ${lib.optionalString (config.gtk.iconTheme != null) ''

        [Icons]
        Theme=${config.gtk.iconTheme.name}''}
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

      "org/gnome/shell/app-switcher" = {
        current-workspace-only = true;
      };

      "org/gnome/settings-daemon/plugins/color" = {
        night-light-enabled = false;
        night-light-schedule-automatic = false;
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
        # Stock top bar + overview with an autohide bottom dock. Check an
        # extension's metadata.json lists the running shell version before
        # adding it: search-light and mediacontrols don't support 50 yet.
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
          "notification-icons@jiggak.io"
          "notification-banner-re-reloaded@chrhuang"
          "notification-timeout@chlumskyvaclav.gmail.com"
          "display-brightness-ddcutil@themightydeity.github.com"
        ];
        # GNOME writes UUIDs here when an extension errors or is disabled, and
        # this overrides enabled-extensions. Empty, so every switch resets it.
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

      # Bottom dock, plain autohide, tuned to react fast. hot-keys = false keeps
      # Super+1..9 on workspace switching.
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

      # ArcMenu: centered top-bar app menu plus an Activities button.
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

      "org/gnome/shell/extensions/caffeine" = {
        user-enabled = true;
        restore-state = true;
        show-indicator = "always";
      };

      "org/gnome/shell/extensions/clipboard-indicator" = {
        toggle-menu = [ "<Super>v" ];
        clear-history = [ "<Super><Shift>v" ];
        paste-on-select = true;
        notify-on-copy = false;
        history-size = 200;
        move-item-first = true;
      };

      # Notification banners: anchored to top-right corner, 3.5s auto-dismiss
      "org/gnome/shell/extensions/notification-banner-re-reloaded" = {
        anchor-horizontal = 2; # Top-right corner
        anchor-vertical = 0; # Top
        animation-direction = 2; # Slide in from right
        animation-time = 200;
      };

      "org/gnome/shell/extensions/notification-timeout" = {
        timeout = 3500; # Auto-dismiss after 3.5 seconds
        ignore-idle = true;
        always-normal = true;
      };

      "org/gnome/shell/extensions/notification-icons" = {
        show-count = true;
      };

      "org/gnome/shell/extensions/tiling-assistant" = {
        enable-gradient = true;
        active-window-hint = 1; # Pulse hint
        # Catppuccin Mocha blue, matching the system theme and rofi.
        active-window-hint-color = "rgba(137, 180, 250, 0.5)";
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
          "Internet"
        ];
      };

      # Hand-listed: no category is narrow enough to match all four.
      "org/gnome/desktop/app-folders/folders/Virtualization" = {
        name = "Virtualization";
        apps = [
          "io.github.dvlv.boxbuddyrs.desktop"
          "com.github.marhkb.Pods.desktop"
          "virt-manager.desktop"
          "org.gnome.Connections.desktop"
        ];
      };

      # "IDE", not "Development": Pods also carries Development.
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
        # GNOME seeds a default "apps" list here, and Utilities matches before
        # Media, so it steals apps like Decibels. Empty overrides it.
        apps = [ ];
      };

      # Folders match narrow freedesktop categories only; "Utility" or
      # "Graphics" would swallow half the grid.
      "org/gnome/desktop/app-folders/folders/FleetServices" = {
        name = "Fleet Services";
        categories = [ "WebBrowser" ];
        # The service PWA launchers declare WebBrowser; exclude the real browsers.
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

      # Last in folder-children, so it only collects the Network apps no folder
      # above claims (Connections and Pods stay in Virtualization, the service
      # PWAs in Fleet Services): chat (Buzz, Signal, Element, Discord, Slack),
      # remote desktop, feeds, transfers. Chrome stays on the dock.
      "org/gnome/desktop/app-folders/folders/Internet" = {
        name = "Internet";
        categories = [ "Network" ];
        excluded-apps = [
          "google-chrome-stable.desktop"
          "google-chrome.desktop"
          "com.google.Chrome.desktop"
          "chromium-pentest.desktop"
        ];
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

    # Mutter lacks zwlr_data_control_manager_v1, so Bitwarden's clipboard
    # fails on Wayland (bitwarden/clients#13431). Shadow its desktop file and
    # drop NIXOS_OZONE_WL so it runs on XWayland.
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
