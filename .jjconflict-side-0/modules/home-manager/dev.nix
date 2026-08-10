{ pkgs, ... }:

{
  home = {
    packages = with pkgs; [
      # -- Stable Dev Tools --
      gh # GitHub CLI
      nil # Nix LSP
      nixfmt # Nix Formatter
      pre-commit

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

      # -- Daily-driver AI CLI (needed in every repo, devshell or not) --
      claude-code

      # -- Volatile AI & Pentesting tools moved to DevShells --
      # Run: just pentest   (Wireshark, Metasploit, Burp, etc.)
      # Run: just ai-dev    (copilot-cli, gemini-cli, fabric-ai, llm)
    ];

    # Automatically install pre-commit hooks when entering the shell
    # file.".zshrc".text = ''
    #   pre-commit install > /dev/null 2>&1
    # '';

    # Helper to bootstrap LazyVim
    # shellAliases.lazy-install = "git clone https://github.com/LazyVim/starter ~/.config/nvim && nvim";
  };
}
