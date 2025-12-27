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

  ### Helper for Sandboxed xdg-open
  # This replaces the standard xdg-open with one that talks to the portal via DBus.
  # This allows opening apps on the host (like Github Desktop) from within the sandbox.
  mkSandboxedXdgUtils = pkgs.writeShellScriptBin "xdg-open" ''
    # Using dbus-send to communicate with xdg-desktop-portal
    # https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.OpenURI.html

    # Check if we have arguments
    if [ -z "$1" ]; then
      echo "Usage: xdg-open <url>"
      exit 1
    fi

    # Call the OpenURI portal
    # method call time:1735235242.067332 sender=:1.86 -> destination=org.freedesktop.portal.Desktop serial=344 path=/org/freedesktop/portal/desktop; interface=org.freedesktop.portal.OpenURI; member=OpenURI
    #    string ""
    #    string "https://google.com"
    #    array [
    #    ]

    # We use system-bus if DBUS_SESSION_BUS_ADDRESS is not set, but it should be set in sandbox
    ${pkgs.dbus}/bin/dbus-send \
      --session \
      --print-reply \
      --dest=org.freedesktop.portal.Desktop \
      /org/freedesktop/portal/desktop \
      org.freedesktop.portal.OpenURI.OpenURI \
      string:"" \
      string:"$1" \
      array:dict:string:variant:
  '';

  # Wrap the script in a package structure similar to xdg-utils
  sandboxedXdgUtils = pkgs.symlinkJoin {
    name = "sandboxed-xdg-utils";
    paths = [
      mkSandboxedXdgUtils
      pkgs.xdg-utils
    ]; # Prefer our xdg-open over the one in xdg-utils
  };

  # --- GOOGLE CHROME ---
  google-chrome = utils.mkSandboxed {
    package = pkgs.google-chrome;
    name = "google-chrome-stable";
    configDir = "google-chrome";
    extraPackages = [
      sandboxedXdgUtils # Custom wrapper for xdg-open
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
              "/dev/bus/usb"
              "/dev/video0"
              "/dev/video1"
            ]
            ++ (map (i: "/dev/hidraw" + toString i) (pkgs.lib.lists.range 0 49));

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
              "/sys/devices" # Required for full device tree traversal
              "/run/udev/data" # Required for device property lookups
              "/run/udev"
            ];
          };
          env = {
            # Enable System Integration (Open Links/Apps) via DBus
            DBUS_SESSION_BUS_ADDRESS = sloth.env "DBUS_SESSION_BUS_ADDRESS";
            # Force Chrome to use the standard profile directory despite binary rename
            CHROME_USER_DATA_DIR = sloth.concat' sloth.homeDir "/.config/google-chrome";
            # Fix Wayland popup/dialog rendering issues
            NIXOS_OZONE_WL = "1";
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

  # --- LM STUDIO ---
  lmstudio = utils.mkSandboxed {
    package = pkgs.lmstudio;
    name = "lmstudio";
    presets = [
      "wayland"
      "gpu"
      "audio"
      "network"
    ];
    extraPerms = _: {
      bubblewrap.bind = {
        rw = [
          # Model storage
          "/images/lmstudio"
        ];
      };
    };
  };
}
