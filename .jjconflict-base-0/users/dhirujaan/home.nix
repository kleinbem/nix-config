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
    firefox-beta
    wofi # Wayland App Launcher
    pavucontrol # Audio control
    grim # Screenshot
    slurp # Select region
    wl-clipboard # Clipboard
  ];

  # Lightweight Sway Configuration
  wayland.windowManager.sway = {
    enable = true;
    checkConfig = false; # Disable check to avoid fontconfig issues in the build sandbox
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
