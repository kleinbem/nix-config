{ pkgs, ... }:

let
  commonData = import ./code-common/settings.nix;

  # Import Modular Extensions
  extensionsCommon = import ./code-common/extensions/common.nix { inherit pkgs; };
  extensionsVSCode = import ./code-common/extensions/vscode.nix { inherit pkgs; };

in
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode-fhs;
    mutableExtensionsDir = false;
    profiles.default = {
      userSettings = commonData.settings // {
        "extensions.autoUpdate" = false;
        "extensions.autoCheckUpdates" = false;
      };
      inherit (commonData) keybindings;
      extensions =
        with pkgs.vscode-extensions;
        [
          # ⚠️ KEEP REMOTE-SSH HERE (VS Code Exclusive)
          ms-vscode-remote.remote-ssh
        ]
        ++ extensionsCommon
        ++ extensionsVSCode;
    };
  };
}
