{ config, pkgs, nixpak, ... }:

let
  # Import modular apps catalog (relative to this file)
  sandboxedApps = import ./sandboxing/apps.nix { inherit pkgs nixpak; };
in
{
  # User Details
  home = {
    username = "martin";
    homeDirectory = "/home/martin";

    packages = with pkgs; [
      # -- GUI Apps --
      vscode-fhs
      pavucontrol
      nwg-look
      
      # -- Sandboxed Apps --
      sandboxedApps.obsidian
      google-chrome            # Standard (Unsafe) - Disabled
      # sandboxedApps.google-chrome  # Nixpak (Safe) - Enabled

      # -- Dev & AI Tools --
      gh                  # GitHub CLI
      github-copilot-cli  
      gemini-cli          # Google Gemini (Free Tier)
      claude-code
      
      llm
      nil           
      nixfmt-rfc-style

      # -- Security & Keys --
      keepassxc           # Offline Password Manager
      yubikey-manager     # CLI Tool (Essential for scripts/backend)
      yubioath-flutter    # Modern GUI (Replaces yubikey-manager-qt)
      rbw
      pinentry-gnome3      

      # -- CLI Utils --
      just
      jq
      ripgrep
      fd
      tree
    ];
    
    stateVersion = "24.11"; 
  };

  # Git configuration
  programs = {
    git = {
      enable = true;
      settings = {
        user = {
          name = "Martin Kleinberger";
          email = "martin.kleinberger@gmail.com";
        };
      };
    };

    neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    waybar.enable = true;
    home-manager.enable = true;
  };
}
