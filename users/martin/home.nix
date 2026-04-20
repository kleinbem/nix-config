{
  pkgs,
  my,
  ...
}:
let
  keys = import ../../modules/nixos/keys.nix;
in
{
  imports = [
    ../../modules/home-manager/default.nix
  ];

  modules.opencode.enable = true;

  # User Details
  home = {
    inherit (my) username;
    homeDirectory = my.home;
    stateVersion = "25.11";
    sessionVariables = {
      DEFAULT_BROWSER = "${pkgs.firefox-beta}/bin/firefox -P standard";
      BROWSER = "${pkgs.firefox-beta}/bin/firefox -P standard";
    };
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "firefox-standard.desktop" ];
      "x-scheme-handler/http" = [ "firefox-standard.desktop" ];
      "x-scheme-handler/https" = [ "firefox-standard.desktop" ];
      "x-scheme-handler/about" = [ "firefox-standard.desktop" ];
      "x-scheme-handler/unknown" = [ "firefox-standard.desktop" ];
    };
  };

  programs = {
    firefox-browser.enable = true;
    home-manager.enable = true;

    # Inject hardware-protected signing keys from centralized proxy
    git.settings.user.signingKey = "key::${keys.ssh.yubikey}";
    jujutsu.settings.signing.key = "key::${keys.ssh.yubikey}";
  };

  # Silencing evaluation warnings from newer Home Manager
  # (Using null adopts the new default behavior)
  gtk.gtk4.theme = null;
}
