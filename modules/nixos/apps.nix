{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    comma # Run any nixpkgs binary instantly: , cowsay "hi"
    lnav # Advanced log file viewer
    fastfetch # Modern neofetch replacement
    zoxide # Smarter cd command
    fzf # Fuzzy finder
  ];

  # Shell integrations for system shells
  programs.zsh.interactiveShellInit = ''
    eval "$(zoxide init zsh)"
  '';
  programs.bash.interactiveShellInit = ''
    eval "$(zoxide init bash)"
  '';

  # fzf default options
  environment.variables = {
    FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border";
  };
}
