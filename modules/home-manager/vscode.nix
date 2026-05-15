{ pkgs, ... }:

let
  commonData = import ./code-common/settings.nix;

  # Use the nix-vscode-extensions overlay for consistent extension management.
  # The overlay is configured in modules/nixos/common.nix.
  vsx = pkgs.open-vsx;
  mkt = pkgs.vscode-marketplace;

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
          # ⚠️ VS Code Exclusive (not supported by Cursor/Windsurf/Antigravity)
          ms-vscode-remote.remote-ssh
        ]
        # --- Common (shared with all editors via nix-vscode-extensions overlay) ---
        ++ [
          vsx.mkhl.direnv
          vsx.jnoortheen.nix-ide
          vsx.tamasfe.even-better-toml
          vsx.eamodio.gitlens
          vsx.waderyan.gitblame
          vsx.ms-python.python
          vsx.usernamehw.errorlens
          vsx.gruntfuggly.todo-tree
          vsx.hashicorp.terraform
        ]
        # --- AI ---
        ++ [
          mkt.github.copilot
          mkt.rooveterinaryinc.roo-cline
          mkt.github.copilot-chat
          # Claude-Code removed because it depends on the broken Wireshark package.
        ];
    };
  };
}
