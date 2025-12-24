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
    vscode-fhs
    code-cursor # AI Code Editor (New in 25.05)
    antigravity-fhs
    pavucontrol
    nwg-look
    mission-center # System Monitor (Task Manager)
    firewalld-gui # GUI for Firewalld
    zathura # PDF Viewer
    imv # Image Viewer
    p7zip # Archives

    # -- Sandboxed Apps --
    sandboxedApps.obsidian
    sandboxedApps.mpv # Nixpak (Safe)
    sandboxedApps.google-chrome # Nixpak (Safe) - Banking
    sandboxedApps.lmstudio # Nixpak (Safe)
    chromium # Fallback (Unsafe) - Local Dev

  ];

  programs.waybar.enable = true;

  systemd.user.services.rclone-gdrive-mount = {
    Unit = {
      Description = "Mount Google Drive via Rclone";
      After = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      # Ensure the mount point exists: mkdir -p ~/GoogleDrive
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone mount gdrive: %h/GoogleDrive \
          --vfs-cache-mode full \
          --vfs-cache-max-size 10G \
          --vfs-cache-max-age 24h \
          --dir-cache-time 1000h \
          --log-level INFO
      '';
      ExecStop = "/run/wrappers/bin/fusermount -u %h/GoogleDrive";
      Restart = "on-failure";
      RestartSec = "10s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
