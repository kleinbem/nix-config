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
        # 1. Camera Access (for Google Meet/Zoom)
        bind.dev = [ 
          "/dev/video0" 
          "/dev/video1"
        ]; 

        # 2. File Access
        bind.rw = [
          # Downloads
          (sloth.concat' sloth.homeDir "/Downloads")
          
          # Config & Cache (Crucial for keeping you logged in)
          (sloth.concat' sloth.homeDir "/.config/google-chrome")
          (sloth.concat' sloth.homeDir "/.cache/google-chrome")
        ];
      };
    };
  };
}