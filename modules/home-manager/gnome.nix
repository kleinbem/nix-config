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
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        enable-hot-corners = false;
        show-battery-percentage = true;
        font-name = "Inter 11";
        document-font-name = "Inter 11";
        monospace-font-name = "JetBrainsMono Nerd Font 10";
        clock-show-weekday = true;
        clock-show-date = true;
        gtk-enable-primary-paste = true;
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
        experimental-features = [
          "scale-monitor-framebuffer"
          "variable-refresh-rate"
        ];
      };

      "org/gnome/settings-daemon/plugins/color" = {
        night-light-enabled = true;
        night-light-schedule-automatic = true;
      };

      "org/gnome/desktop/peripherals/touchpad" = {
        tap-to-click = true;
        natural-scroll = true;
      };

      "org/gnome/desktop/peripherals/mouse" = {
        accel-profile = "flat";
      };

      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = [
          "blur-my-shell@aunetx"
          "dash-to-dock@micxgx.gmail.com"
          "appindicatorsupport@rgcjonas.gmail.com"
          "just-perfection-desktop@just-perfection"
          "Vitals@corecoding.com"
          "caffeine@patapon.info"
          "clipboard-indicator@tudmotu.com"
          "gsconnect@andyholmes.github.io"
          "space-bar@luchrioh"
          "search-light@icedman.github.com"
          "drive-menu@gnome-shell-extensions.gcampax.github.com"
          "tiling-assistant@leleat-on-github"
          "logo-menu@pauguic.github.io"
        ];
        favorite-apps = [
          "firefox-standard.desktop"
          "org.gnome.Thunderbird.desktop"
          "org.gnome.Nautilus.desktop"
          "gnome-software.desktop"
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

      "org/gnome/shell/extensions/dash-to-dock" = {
        dash-max-icon-size = 42;
        dock-position = "BOTTOM";
        extend-height = false;
        dock-fixed = true;
        autohide = false;
        show-apps-at-top = true;
      };

      "org/gnome/shell/extensions/just-perfection" = {
        accessibility-menu = false;
        search = true;
      };

      "org/gnome/shell/extensions/space-bar/appearance" = {
        workspace-margin = 4;
      };

      "org/gnome/shell/extensions/search-light" = {
        shortcut-search = [ "<Super>space" ];
        width-percentage = 35;
        background-color = [
          0.0
          0.0
          0.0
          0.8
        ];
        border-color = [
          0.23
          0.23
          0.23
          1.0
        ];
        border-radius = 1.65;
        border-thickness = 1;
        scale-height = 0.15;
        scale-width = 0.10;
      };

      "org/gnome/shell/extensions/logo-menu" = {
        hide-forcequit = true;
        menu-button-icon-image = 30;
        menu-button-icon-size = 20;
        menu-button-system-monitor = "${pkgs.mission-center}/bin/missioncenter";
        menu-button-terminal = "ptyxis";
        show-activities-button = true;
        symbolic-icon = true;
      };

      "org/gnome/shell/extensions/tiling-assistant" = {
        enable-gradient = true;
        active-window-hint = 1; # Pulse hint
        active-window-hint-color = "rgba(53, 132, 228, 0.5)";
      };

      # --- Bluefin-inspired Improvements ---
      "org/gnome/desktop/input-sources" = {
        sources = [
          (lib.hm.gvariant.mkTuple [
            "xkb"
            "ml+us-intl"
          ])
        ];
        current = lib.hm.gvariant.mkUint32 0;
      };

      "org/gnome/desktop/app-folders" = {
        folder-children = [
          "Containers"
          "Development"
          "Productivity"
          "Utilities"
        ];
      };

      "org/gnome/desktop/app-folders/folders/Containers" = {
        name = "Containers";
        apps = [
          "io.github.dvlv.boxbuddyrs.desktop"
          "com.github.marhkb.Pods.desktop"
        ];
      };

      "org/gnome/desktop/app-folders/folders/Development" = {
        name = "Development";
        apps = [
          "org.gnome.Builder.desktop"
          "io.podman_desktop.PodmanDesktop.desktop"
          "virt-manager.desktop"
          "code.desktop"
          "dev-pod.desktop"
        ];
      };

      "org/gnome/desktop/app-folders/folders/Productivity" = {
        name = "Productivity";
        apps = [
          "org.gnome.Papers.desktop"
          "simple-scan.desktop"
          "org.gnome.Connections.desktop"
        ];
      };

      "org/gnome/desktop/app-folders/folders/Utilities" = {
        name = "Utilities";
        categories = [ "X-GNOME-Utilities" ];
      };

      "org/gnome/desktop/privacy" = {
        report-technical-problems = false;
      };

      # --- Productivity Keybindings ---
      "org/gnome/settings-daemon/plugins/media-keys" = {
        custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-terminal/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-terminal-alt/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-mission-center/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-alpaca/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-smile/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-smile-alt/"
        ];
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

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-alpaca" = {
        binding = "<Control><Alt>BackSpace";
        command = "alpaca";
        name = "Launch Alpaca (AI)";
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
  };
}
