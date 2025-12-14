{ pkgs, nixpak, ... }:

let
  utils = import ./utils.nix { inherit pkgs nixpak; };
in
{
  # --- OBSIDIAN ---
  obsidian = utils.mkSandboxed {
    package = pkgs.obsidian;
    extraPerms = { sloth, ... }: {
      bubblewrap.bind.rw = [
        (sloth.concat' sloth.homeDir "/Documents")
      ];
    };
  };

  # --- GOOGLE CHROME ---
  google-chrome = utils.mkSandboxed {
    package = pkgs.google-chrome;
    extraPerms = { sloth, ... }: {
      bubblewrap = {
        # 1. Device Access
        bind.dev = [ 
          "/dev/video0" # Webcam
          "/dev/video1"
          "/dev/dri"    # GPU Acceleration
        ];

        # 2. File & Socket Access
        bind.rw = [
          # Audio
          (sloth.concat' sloth.runtimeDir "/pipewire-0")

          # Downloads
          (sloth.concat' sloth.homeDir "/Downloads")
          
          # Cache (Speed)
          # Note: ~/.config/google-chrome is already bound by utils.nix
          (sloth.concat' sloth.homeDir "/.cache/google-chrome")

          # --- PWA Integration ---
          # 1. Allow writing .desktop files (Launcher entries)
          (sloth.concat' sloth.homeDir "/.local/share/applications")
          # 2. Allow writing icons
          (sloth.concat' sloth.homeDir "/.local/share/icons")
          # 3. Allow registering as Default App for links (MIME types)
          (sloth.concat' sloth.homeDir "/.config/mimeapps.list")
        ];

        bind.ro = [
           # --- UI Consistency ---
           # User-installed fonts
           (sloth.concat' sloth.homeDir "/.local/share/fonts")
           # GTK Bookmarks (for 'Recent Files' in upload dialogs)
           (sloth.concat' sloth.homeDir "/.config/gtk-3.0")
        ];
      };
    };
  };
}