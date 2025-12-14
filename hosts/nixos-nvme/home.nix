{ config, pkgs, nixpak, ... }:

let
  # Import modular apps catalog (relative to this file)
  sandboxedApps = import ./sandboxing/apps.nix { inherit pkgs nixpak; };
in
{
  # User Details
  home.username = "martin";
  home.homeDirectory = "/home/martin";

  # Targets genericLinux is not needed for pure NixOS
  # targets.genericLinux.enable = true; 

  home.packages = with pkgs; [
    # -- GUI Apps --
    google-chrome
    vscode-fhs
    pavucontrol
    nwg-look
    
    # -- Sandboxed Apps --
    sandboxedApps.obsidian
    # sandboxedApps.google-chrome

    # -- Dev & AI Tools --
    gemini-cli
    claude-code
    copilot-cli
    awscli2
    llm
    nil           
    # Nix language server
    nixfmt-rfc-style
    
    # -- CLI Utils --
    just
    jq
    ripgrep
    fd
    tree
  ];

  # Git configuration
  programs.git = {
    enable = true;
    userName = "Martin Kleinberger";
    userEmail = "martin.kleinberger@gmail.com";
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.waybar.enable = true;

  programs.home-manager.enable = true;

  # State version
  home.stateVersion = "24.11"; 
}