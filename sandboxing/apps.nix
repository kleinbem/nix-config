# sandboxing/apps.nix
{ pkgs, nixpak, ... }:

let
  utils = import ./utils.nix { inherit pkgs nixpak; };
in
{
  # --- OBSIDIAN ---
  # Only sees ~/Documents. Cannot see Code, SSH keys, or Photos.
  obsidian = utils.mkSandboxed {
    package = pkgs.obsidian;
    extraPerms = { sloth, ... }: {
      bubblewrap.bind.rw = [
        (sloth.concat' sloth.homeDir "/Documents")
      ];
    };
  };

  # --- DISCORD ---
  # Has access to Downloads and Camera/GPU, but nothing else.
  discord = utils.mkSandboxed {
    package = pkgs.discord;
    extraPerms = { sloth, ... }: {
      bubblewrap.bind.dev = [ "/dev/video0" "/dev/dri" ]; # Webcam + GPU
      bubblewrap.bind.rw = [
        (sloth.concat' sloth.homeDir "/Downloads")
      ];
    };
  };
}