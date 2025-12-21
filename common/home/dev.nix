{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # -- Dev & AI Tools --
    gh # GitHub CLI
    github-copilot-cli
    gemini-cli
    claude-code

    llm
    nil
    nixfmt-rfc-style

    # -- LazyVim Prerequisites --
    ripgrep
    fd
    gcc # For Treesitter
    gnumake
    nodejs_22 # For LSPs/Copilot
    unzip
    tree-sitter
    xclip # System clipboard support
    wl-clipboard
  ];

  # Helper to bootstrap LazyVim
  home.shellAliases.lazy-install = "git clone https://github.com/LazyVim/starter ~/.config/nvim && nvim";

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
}
