{ pkgs, ... }:

{
  programs.vscode = {
    enable = true;
    # package = pkgs.vscode; # usage of FHS is debated, sticking to standard for now.

    profiles.default = {
      # Recommended Extensions
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
        eamodio.gitlens
        github.copilot
        github.copilot-chat
        usernamehw.errorlens
        ms-vscode-remote.remote-ssh
      ];

      # Settings Sync
      userSettings = {
        "editor.fontFamily" = "'Fira Code', 'Droid Sans Mono', 'monospace', monospace";
        "editor.fontLigatures" = true;
        "workbench.colorTheme" = "Default Dark Modern";
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nil";
        "nix.serverSettings" = {
          "nil" = {
            "formatting" = {
              "command" = [ "nixfmt" ];
            };
          };
        };
      };
    };
  };
}
