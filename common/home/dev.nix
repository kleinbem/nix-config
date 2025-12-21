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
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
}
