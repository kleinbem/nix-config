_:

{
  imports = [
    ../../modules/home-manager/terminal.nix
    ../../modules/home-manager/dev.nix
    ../../modules/home-manager/desktop.nix
    ../../modules/home-manager/security.nix
    ../../modules/home-manager/pentesting.nix
    ../../modules/home-manager/vscode.nix
    ../../modules/home-manager/nixvim.nix
    ../../modules/home-manager/secrets.nix
    ../../modules/home-manager/opencode.nix
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
