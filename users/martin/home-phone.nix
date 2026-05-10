{
  lib,
  ...
}:
{
  # This is a slimmed-down version of your home config for Android
  home = {
    username = lib.mkForce "martin";
    homeDirectory = lib.mkForce "/data/data/com.termux.nix/files/home";
    stateVersion = "24.05";
  };

  # Only include terminal-based programs
  programs = {
    home-manager.enable = true;
    zsh.enable = true;
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    git = {
      enable = true;
      settings = {
        user = {
          name = "Martin";
          email = "your@email.com";
        };
      };
    };
  };

  # Add any other phone-specific CLI tools here
}
