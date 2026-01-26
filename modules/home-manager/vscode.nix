{ pkgs, ... }:

let
  commonData = import ./code-common/settings.nix;
  # Import the AUTO-GENERATED extensions file
  commonExtensions = import ./code-common/extensions.nix { inherit pkgs; };
in
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode-fhs;
    profiles.default = {
      userSettings = commonData.settings;
      inherit (commonData) keybindings;
      extensions =
        with pkgs.vscode-extensions;
        [
          # ⚠️ KEEP REMOTE-SSH HERE (VS Code Exclusive)
          ms-vscode-remote.remote-ssh
        ]
        ++ commonExtensions;
    };
  };
}
