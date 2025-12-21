{ pkgs, nixpak, ... }:

let
  utils = import ./utils.nix { inherit pkgs nixpak; };
in
{
  # --- OBSIDIAN ---
  obsidian = utils.mkSandboxed {
    package = pkgs.obsidian;
    extraPerms =
      { sloth, ... }:
      {
        bubblewrap.bind.rw = [
          (sloth.concat' sloth.homeDir "/Documents")
        ];
      };
  };

  # --- GOOGLE CHROME ---
  # --- GOOGLE CHROME ---
  google-chrome = utils.mkSandboxed {
    package = pkgs.google-chrome;
    extraPerms =
      { sloth, ... }:
      {
        bubblewrap = {
          bind = {
            # 1. Device Access
            dev = [
              "/dev/video0" # Webcam
              "/dev/video1"
              "/dev/dri" # GPU Acceleration
            ];

            # 2. File & Socket Access
            rw = [
              # Audio
              (sloth.concat' sloth.runtimeDir "/pipewire-0")

              # Downloads
              (sloth.concat' sloth.homeDir "/Downloads")

              # Cache
              (sloth.concat' sloth.homeDir "/.cache/google-chrome")

              # --- PWA Integration ---
              (sloth.concat' sloth.homeDir "/.local/share/applications")
              (sloth.concat' sloth.homeDir "/.local/share/icons")
              (sloth.concat' sloth.homeDir "/.config/mimeapps.list")
            ];

            # 3. Read Only Access
            ro = [
              # User-installed fonts
              (sloth.concat' sloth.homeDir "/.local/share/fonts")
              # GTK Bookmarks
              (sloth.concat' sloth.homeDir "/.config/gtk-3.0")
            ];
          };
          env = {
            # Enable System Integration (Open Links/Apps) via DBus
            DBUS_SESSION_BUS_ADDRESS = sloth.env "DBUS_SESSION_BUS_ADDRESS";
          };
        };
      };
  };
}
