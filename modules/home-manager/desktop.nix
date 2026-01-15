{
  pkgs,
  nixpak,
  ...
}:

let
  # Import modular apps catalog
  # Import modular apps catalog
  # We are in modules/home-manager/desktop.nix, so we go up to modules, then to nixos/nixpak
  sandboxedApps = import ../nixos/nixpak/apps.nix { inherit pkgs nixpak; };

in
{
  home.packages = with pkgs; [
    # -- GUI Apps --
    # vscode-fhs (Moved to declarative module)
    code-cursor-fhs # AI Code Editor (FHS Version)
    antigravity-fhs
    warp-terminal # Rust-based AI Terminal
    pavucontrol
    nwg-look
    mission-center # System Monitor (Task Manager)
    firewalld-gui # GUI for Firewalld
    zathura # PDF Viewer
    imv # Image Viewer
    p7zip # Archives
    rclone-browser # GUI for Rclone
    restic-browser # GUI for Restic Backups
    restic # CLI Tool (Required for Restic Browser)
    obs-studio # Streaming/Recording Software

    # --- Communication ---
    sandboxedApps.discord
    sandboxedApps.slack
    sandboxedApps.signal-desktop

    # -- Sandboxed Apps --
    sandboxedApps.obsidian
    sandboxedApps.mpv # Nixpak (Safe)
    sandboxedApps.google-chrome # Standard Profile
    sandboxedApps.google-chrome-vault
    sandboxedApps.google-chrome-hazard
    sandboxedApps.lmstudio # Nixpak (Safe)
    sandboxedApps.bitwarden # Nixpak (Safe) - Password Manager
    # sandboxedApps.github-desktop # Nixpak (Safe) - Code
    github-desktop # Standard (Unsafe) - Temporarily disabled sandbox for auth debugging
    chromium # Fallback (Unsafe) - Local Dev

    # Math and Matrix stuff. Using 'octaveFull' to get the standard packages included.
    octaveFull

    # Modern LaTeX alternative. Much faster for writing docs.
    typst
    tinymist # autocompletion in VS Code/Neovim (formerly typst-lsp)
    nixd # Nix Language Server
  ];

  # Force Qt apps to use GTK theme (fixes rclone-browser dark mode)
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/x-github-client" = [ "github-desktop.desktop" ];
      "text/html" = [ "google-chrome.desktop" ];
      "x-scheme-handler/http" = [ "google-chrome.desktop" ];
      "x-scheme-handler/https" = [ "google-chrome.desktop" ];
      "x-scheme-handler/about" = [ "google-chrome.desktop" ];
      "x-scheme-handler/unknown" = [ "google-chrome.desktop" ];
    };
  };

  # Create a custom "Fortress" launcher for BOI
  xdg.desktopEntries = {

    # ---------------------------------------------------------
    # 1. THE VAULT BROWSER (Secure, No Extensions)
    # ---------------------------------------------------------
    "chrome-vault-browser" = {
      name = "Google Chrome (Secure Vault)";
      genericName = "Secure Browser";

      # 1. Add '--class' so the Window Manager knows this is different from normal Chrome
      # Nixpak handles user-data-dir!
      exec = "${sandboxedApps.google-chrome-vault}/bin/google-chrome-vault --disable-extensions --no-first-run --class=google-chrome-vault";

      terminal = false;
      icon = "google-chrome";
      categories = [
        "Network"
        "WebBrowser"
      ];

      # 2. Better UX
      startupNotify = true;

      # 3. Match the window to this icon (Critical for Dock/Taskbar)
      settings = {
        StartupWMClass = "google-chrome-vault";
      };

      # 4. Right-click Menu (Jump List) - Keeps you in the Vault
      actions = {
        "new-window" = {
          name = "New Secure Window";
          exec = "${sandboxedApps.google-chrome-vault}/bin/google-chrome-vault --disable-extensions --class=google-chrome-vault";
        };
        # Optional: Incognito inside the Vault (Clean + Secure)
        "new-incognito" = {
          name = "New Secure Incognito";
          exec = "${sandboxedApps.google-chrome-vault}/bin/google-chrome-vault --disable-extensions --incognito --class=google-chrome-vault";
        };
      };
    };

    # ---------------------------------------------------------
    # 2. THE HAZARD BROWSER (Social Media, Isolated)
    # ---------------------------------------------------------
    "chrome-hazard-browser" = {
      name = "Google Chrome (Hazard Zone)";
      genericName = "Unsafe Browser";

      # 1. Add '--class'
      # Nixpak handles user-data-dir!
      exec = "${sandboxedApps.google-chrome-hazard}/bin/google-chrome-hazard --no-first-run --class=google-chrome-hazard";

      terminal = false;
      icon = "google-chrome";
      categories = [
        "Network"
        "WebBrowser"
      ];

      startupNotify = true;

      settings = {
        StartupWMClass = "google-chrome-hazard";
      };

      actions = {
        "new-window" = {
          name = "New Hazard Window";
          exec = "${sandboxedApps.google-chrome-hazard}/bin/google-chrome-hazard --class=google-chrome-hazard";
        };
        "new-incognito" = {
          name = "New Hazard Incognito";
          exec = "${sandboxedApps.google-chrome-hazard}/bin/google-chrome-hazard --incognito --class=google-chrome-hazard";
        };
      };
    };
  };

  programs.waybar.enable = true;

  systemd.user.services.rclone-gdrive-mount = {
    Unit = {
      Description = "Mount Google Drive via Rclone";
      After = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      Environment = "PATH=/run/wrappers/bin:$PATH";
      # Ensure the mount point exists: mkdir -p ~/GoogleDrive
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/GoogleDrive";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone mount gdrive: %h/GoogleDrive \
          --vfs-cache-mode full \
          --vfs-cache-max-size 10G \
          --vfs-cache-max-age 24h \
          --dir-cache-time 1000h \
          --log-level INFO
      '';
      ExecStop = "/run/wrappers/bin/fusermount3 -u %h/GoogleDrive";
      Restart = "on-failure";
      RestartSec = "10s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.rclone-onedrive-mount = {
    Unit = {
      Description = "Mount OneDrive via Rclone";
      After = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      Environment = "PATH=/run/wrappers/bin:$PATH";
      # Ensure the mount point exists: mkdir -p ~/OneDrive
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/OneDrive";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone mount onedrive: %h/OneDrive \
          --vfs-cache-mode full \
          --vfs-cache-max-size 10G \
          --vfs-cache-max-age 24h \
          --dir-cache-time 1000h \
          --log-level INFO
      '';
      ExecStop = "/run/wrappers/bin/fusermount3 -u %h/OneDrive";
      Restart = "on-failure";
      RestartSec = "10s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
