{ config, pkgs, nixpak, ... }: # <--- 1. We accept 'nixpak' here

let
  # 2. Load your modular apps catalog
  # This looks for ./sandboxing/apps.nix
  sandboxedApps = import ./sandboxing/apps.nix { inherit pkgs nixpak; };
in
{
  # User Details
  home.username = "martin";
  home.homeDirectory = "/home/martin";

  # NOTE: On NixOS, 'targets.genericLinux' is usually not needed. 
  # It is mostly for using Home Manager on Ubuntu/Debian. 
  # You can safely remove this line if you are fully on NixOS.
  targets.genericLinux.enable = true; 

  home.packages = with pkgs; [
    # -- GUI Apps --
    google-chrome
    vscode-fhs
    pavucontrol
    nwg-look
    
    # -- Sandboxed Apps --
    # This replaces the standard 'obsidian' package
    sandboxedApps.obsidian
    # sandboxedApps.google-chrome

    # -- Dev & AI Tools --
    gemini-cli
    claude-code
    copilot-cli
    awscli2
    llm
    nil              # Nix language server
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