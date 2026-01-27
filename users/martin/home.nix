_:

{
  imports = [
    ../../modules/home-manager/default.nix
  ];

  modules.opencode.enable = true;

  # User Details
  home = {
    username = "martin";
    homeDirectory = "/home/martin";
    stateVersion = "24.11";
  };

  # System Control Justfile
  home.file.".justfile".source = ../../modules/home-manager/files/justfile;

  # Host-specific tweaks can stay here if needed
  # (e.g. monitor config, unique vars)
  programs.home-manager.enable = true;
}
