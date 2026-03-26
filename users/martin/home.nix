{
  my,
  lib,
  ...
}:
{
  imports = [ ../../modules/home-manager/default.nix ];

  modules.opencode.enable = true;

  # User Details
  home = {
    inherit (my) username;
    homeDirectory = my.home;
    stateVersion = "25.11";
  };

  programs = {
    zen-browser.enable = true;
    home-manager.enable = true;
    git.signing.format = lib.mkDefault "ssh";
  };

  # Silencing evaluation warnings from newer Home Manager
  gtk.gtk4.theme = lib.mkDefault "Adwaita"; # Fallback or specific theme
}
