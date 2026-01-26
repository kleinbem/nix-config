{
  pkgs,
  lib,

  nixpak,
  ...
}:

let
  # Import modular apps catalog
  sandboxedApps = import ../nixos/nixpak/apps.nix { inherit pkgs nixpak; };

  commonData = import ./code-common/settings.nix;
  commonExtensionsList = import ./code-common/extensions.nix { inherit pkgs; };
  commonExtensions = pkgs.symlinkJoin {
    name = "vscode-extensions-bundle";
    paths = commonExtensionsList;
  };

  # The Unified "Code Family"
  codeFamily = [
    {
      name = "Antigravity";
      configDir = "antigravity/User";
      extDir = ".antigravity/extensions";
    }
    {
      name = "Cursor";
      configDir = "Cursor/User";
      extDir = ".cursor/extensions";
    }
    {
      name = "Windsurf";
      configDir = ".codeium/windsurf/User";
      extDir = ".codeium/windsurf/extensions";
    }
  ];

  # Helper to write JSON config
  mkConfigs = app: {
    "${app.configDir}/settings.json".text = builtins.toJSON commonData.settings;
    "${app.configDir}/keybindings.json".text = builtins.toJSON commonData.keybindings;
  };

in
{
  imports = [
    ./mcp.nix
  ];

  home = {
    packages = with pkgs; [
      antigravity-fhs
      code-cursor-fhs
      windsurf

      # -- GUI Apps --
      # Unified Code Platform Editors
      antigravity-fhs
      code-cursor-fhs
      windsurf

      # vscode-fhs (Moved to declarative module)
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
      sandboxedApps.google-chrome-stable # Standard Profile (Renamed from google-chrome)
      sandboxedApps.google-chrome-stable-vault
      sandboxedApps.google-chrome-stable-hazard
      sandboxedApps.lmstudio # Nixpak (Safe)
      sandboxedApps.bitwarden # Nixpak (Safe) - Password Manager
      # sandboxedApps.github-desktop # Nixpak (Safe) - Code
      github-desktop # Standard (Unsafe) - Temporarily disabled sandbox for auth debugging
      chromium # Fallback (Unsafe) - Local Dev
      pkgs.brotab # Browser Automation (asked by user)
      pkgs.brave # Secure Browser (asked by user)

      # Math and Matrix stuff. Using 'octaveFull' to get the standard packages included.
      octaveFull

      # Modern LaTeX alternative. Much faster for writing docs.
      typst
      tinymist # autocompletion in VS Code/Neovim (formerly typst-lsp)
      nixd # Nix Language Server
    ];

    # Generate declarative config files for all agents
    file = lib.mkMerge (map mkConfigs codeFamily);

    # Sync Extensions Script (Runs on switch)
    # This creates symlinks from the generated extensions.nix profile to each editor's extension dir.
    activation.syncCodeFamily = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${lib.concatMapStrings (app: ''
        echo "⚡ Syncing ${app.name} extensions..."
        mkdir -p $HOME/${app.extDir}

        # Link each extension from the Nix profile (commonExtensions)
        # We iterate over the store path to find the extensions
        for ext in ${commonExtensions}/share/vscode/extensions/*; do
          target="$HOME/${app.extDir}/$(basename $ext)"
          if [ ! -e "$target" ]; then
            ln -sf "$ext" "$target"
          fi
        done

      '') codeFamily}
    '';
  };

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
      "text/html" = [ "google-chrome-stable.desktop" ];
      "x-scheme-handler/http" = [ "google-chrome-stable.desktop" ];
      "x-scheme-handler/https" = [ "google-chrome-stable.desktop" ];
      "x-scheme-handler/about" = [ "google-chrome-stable.desktop" ];
      "x-scheme-handler/unknown" = [ "google-chrome-stable.desktop" ];
    };
  };

  # Create a custom "Fortress" launcher for BOI
  xdg.desktopEntries = {
    # Manual entries removed - now handled by nixpak apps.nix
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
