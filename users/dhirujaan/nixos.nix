{ pkgs, ... }:

{
  users.users.dhirujaan = {
    isNormalUser = true;
    description = "Secondary User Session";
    extraGroups = [
      "video"
      "render"
      "networkmanager"
    ];
    initialPassword = "nix"; # Change this immediately!
    # Linger allows services to run even when not logged in (needed for some nested setups)
    linger = true;
  };

  # Enable Sway for this user (lightweight alternative)
  programs.sway = {
    enable = true;
    extraPackages = with pkgs; [
      swaylock
      swayidle
      wl-clipboard
      mako # notification daemon
      alacritty # lightweight terminal
      waybar # status bar
    ];
  };
}
