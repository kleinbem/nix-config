{ pkgs, nixpak, ... }:

let
  # Import modular apps catalog
  # We are in common/home/desktop.nix, so we go up two levels to common, then to sandboxing
  sandboxedApps = import ../sandboxing/apps.nix { inherit pkgs nixpak; };
in
{
  home.packages = with pkgs; [
    # -- GUI Apps --
    vscode-fhs
    antigravity-fhs
    pavucontrol
    nwg-look
    mpv # Media Player

    # -- Sandboxed Apps --
    sandboxedApps.obsidian
    # google-chrome # Standard (Unsafe) - PWAs
    sandboxedApps.google-chrome # Nixpak (Safe) - Banking
    chromium # Fallback (Unsafe) - Local Dev

    # -- Security & Keys --
    keepassxc # Offline Password Manager
    yubikey-manager # CLI Tool (Essential for scripts/backend)
    yubioath-flutter # Modern GUI (Replaces yubikey-manager-qt)
    rbw
    pinentry-gnome3
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
