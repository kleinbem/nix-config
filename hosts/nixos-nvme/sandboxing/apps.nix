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
          "/dev/dri"    # GPU Acceleration (Essential for Intel iGPU)
        ];

        # 2. File & Socket Access
        bind.rw = [
          # Audio (PipeWire Socket) - REQUIRED for Sound
          (sloth.concat' sloth.runtimeDir "/pipewire-0")

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