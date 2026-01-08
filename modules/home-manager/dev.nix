{ pkgs, ... }:

{
  home = {
    packages = with pkgs; [
      # -- Dev & AI Tools --
      gh # GitHub CLI
      fabric-ai # AI Augmentation Framework
      github-copilot-cli
      # gemini-cli ## temp disabled

      claude-code

      (pkgs.python3Packages.llm.overridePythonAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
      }))
      nil
      nixfmt

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
      pre-commit
    ];

    # Automatically install pre-commit hooks when entering the shell
    file.".zshrc".text = ''
      pre-commit install > /dev/null 2>&1
    '';

    # Helper to bootstrap LazyVim
    # shellAliases.lazy-install = "git clone https://github.com/LazyVim/starter ~/.config/nvim && nvim";
  };
}
