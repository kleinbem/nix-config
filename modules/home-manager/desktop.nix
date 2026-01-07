{ pkgs, nixpak, ... }:

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
    code-cursor # AI Code Editor (New in 25.05)
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
    obs-studio # Streaming/Recording Software

    # -- Sandboxed Apps --
    sandboxedApps.obsidian
    sandboxedApps.mpv # Nixpak (Safe)
    sandboxedApps.google-chrome # Nixpak (Safe) - Banking
    sandboxedApps.lmstudio # Nixpak (Safe)
    sandboxedApps.bitwarden # Nixpak (Safe) - Password Manager
    sandboxedApps.github-desktop # Nixpak (Safe) - Code
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
