_:

{
  imports = [
    ../../modules/home-manager/shell.nix
    ../../modules/home-manager/dev.nix
    ../../modules/home-manager/desktop.nix
    ../../modules/home-manager/security.nix
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
