_:

{
  imports = [
    ../../common/home/shell.nix
    ../../common/home/dev.nix
    ../../common/home/desktop.nix
  ];

  # User Details
  home = {
    username = "martin";
    homeDirectory = "/home/martin";
    stateVersion = "24.11";
  };

  # Host-specific tweaks can stay here if needed
  # (e.g. monitor config, unique vars)
  programs.home-manager.enable = true;
}
