{ config, pkgs, nixpak, ... }:

let
  # Import modular apps catalog (relative to this file)
  sandboxedApps = import ./sandboxing/apps.nix { inherit pkgs nixpak; };
in
{
  # User Details
  home.username = "martin";
  home.homeDirectory = "/home/martin";

  home.packages = with pkgs; [
    # -- GUI Apps --
    vscode-fhs
    pavucontrol
    nwg-look
    
    # -- Sandboxed Apps --
    sandboxedApps.obsidian
    google-chrome
    # sandboxedApps.google-chrome  # Enabled now!

    # -- Dev & AI Tools --
    gh                  # GitHub CLI
    github-copilot-cli  # <--- FIXED: The correct AI Agent
    gemini-cli          # Google Gemini (Free Tier)
    claude-code
    
    # AWS Copilot (Only keep this if you actually use AWS Containers)
    # awscli2 
    
    llm
    nil           
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
    settings = {
      user = {
        name = "Martin Kleinberger";
        email = "martin.kleinberger@gmail.com";
      };
    };
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

  home.stateVersion = "24.11"; 
}