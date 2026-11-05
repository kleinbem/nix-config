{
  pkgs,
  ...
}:

{
  home = {
    username = "dhirujaan";
    homeDirectory = "/home/dhirujaan";
    stateVersion = "25.11";
  };

  imports = [ ];

  programs.home-manager.enable = true;
  programs.alacritty.enable = true;

  home.packages = with pkgs; [
    google-chrome
    wofi # Wayland App Launcher
    pavucontrol # Audio control
    grim # Screenshot
    slurp # Select region
    wl-clipboard # Clipboard
  ];

  # Lightweight Sway Configuration
  wayland.windowManager.sway = {
    enable = true;
    # Off: the config check hits fontconfig issues in the build sandbox.
    # no-link: no upstream issue for the fontconfig failure (closest: nix-community/home-manager#5311).
    checkConfig = false;
    config = {
      modifier = "Mod4";
      terminal = "alacritty";
      menu = "${pkgs.wofi}/bin/wofi --show drun";
      bars = [ { command = "${pkgs.waybar}/bin/waybar"; } ];
      # Premium aesthetic: Subtle gaps and borders
      gaps = {
        inner = 10;
        outer = 5;
      };
      output = {
        "*" = {
          bg = "#1e1e2e solid_color"; # Corrected scaling mode
        };
      };
    };
  };
}
