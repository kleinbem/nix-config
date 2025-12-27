{ pkgs, ... }:

let
  verify-system = pkgs.writeShellApplication {
    name = "verify-system";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
      curl
      pciutils
      gnugrep
      fzf
      fastfetch
      mpv
      ripgrep
      starship
      podman
      nixfmt-rfc-style
      deadnix
      statix
    ];
    text = builtins.readFile ./files/verify-system.sh;
  };
in
{
  environment.systemPackages = [ verify-system ];
}
