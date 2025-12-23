{ pkgs, nixpak, ... }:

let
  utils = import ./utils.nix { inherit pkgs nixpak; };
in
{
  # --- OBSIDIAN ---
  obsidian = utils.mkSandboxed {
    package = pkgs.obsidian;
    presets = [
      "wayland"
      "gpu"
      "network"
    ];
    extraPerms =
      { sloth, ... }:
      {
        bubblewrap.bind.rw = [
          (sloth.concat' sloth.homeDir "/Documents")
        ];
      };
  };

  # --- GOOGLE CHROME ---
  google-chrome = utils.mkSandboxed {
    package = pkgs.google-chrome;
    name = "google-chrome-stable";
    configDir = "google-chrome";
    extraPackages = [
      pkgs.xdg-utils
      pkgs.cosmic-files
    ];
    presets = [
      "network"
      "wayland"
      "audio"
      "gpu"
      "usb"
    ];
    extraPerms =
      { sloth, ... }:
      {
        bubblewrap = {
          bind = {
            # 1. Device Access (Webcams are not covered by standard GPU preset)
            dev = [
              "/dev/video0"
              "/dev/video1"
            ]
            ++ (map (i: "/dev/hidraw" + toString i) (pkgs.lib.lists.range 0 19));

            # 2. File & Socket Access
            rw = [
              # YubiKey / Smart Card (FIDO2)
              "/run/pcscd/pcscd.comm"

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

              # --- Additional Device Metadata ---
              "/sys/class/hidraw"
              "/sys/bus/hid"
            ];
          };
          env = {
            # Enable System Integration (Open Links/Apps) via DBus
            DBUS_SESSION_BUS_ADDRESS = sloth.env "DBUS_SESSION_BUS_ADDRESS";
            # Force Chrome to use the standard profile directory despite binary rename
            CHROME_USER_DATA_DIR = sloth.concat' sloth.homeDir "/.config/google-chrome";
          };
        };
      };
  };

  # --- MPV (Media Player) ---
  mpv = utils.mkSandboxed {
    package = pkgs.mpv;
    name = "mpv";
    presets = [
      "wayland"
      "gpu"
      "audio"
      "network"
    ];
    extraPerms =
      { sloth, ... }:
      {
        bubblewrap.bind = {
          rw = [
            (sloth.concat' sloth.homeDir "/.config/mpv")
          ];
          # Media Folders (Read-only for safety)
          ro = [
            (sloth.concat' sloth.homeDir "/Videos")
            (sloth.concat' sloth.homeDir "/Music")
            (sloth.concat' sloth.homeDir "/Downloads")
          ];
        };
      };
  };
}
