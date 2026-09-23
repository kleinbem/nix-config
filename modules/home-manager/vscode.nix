{
  pkgs,
  config,
  lib,
  ...
}:

let
  commonData = import ./code-common/settings.nix;

  # Use the nix-vscode-extensions overlay for consistent extension management.
  # The overlay is configured in modules/nixos/common.nix.
  vsx = pkgs.open-vsx;
  mkt = pkgs.vscode-marketplace;

  antigravitySettingsJson = pkgs.writeText "antigravity-settings.json" (
    builtins.toJSON (
      commonData.settings
      // {
        "extensions.autoUpdate" = false;
        "extensions.autoCheckUpdates" = false;
      }
    )
  );
  antigravityKeybindingsJson = pkgs.writeText "antigravity-keybindings.json" (
    builtins.toJSON commonData.keybindings
  );

in
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode-fhs;
    mutableExtensionsDir = true;
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
          vsx.waderyan.gitblame
          vsx.visualjj.visualjj
          # vsx.ms-python.python # disabled: jedi-language-server-0.46.0 requires jedi<0.20, nixpkgs has 0.20.0
          vsx.usernamehw.errorlens
          vsx.gruntfuggly.todo-tree
          vsx.hashicorp.terraform
        ]
        # --- AI ---
        ++ [
          mkt.github.copilot
          mkt.rooveterinaryinc.roo-cline
          mkt.github.copilot-chat
          mkt.anthropic.claude-code # Re-enabled to test if upstream wireshark dependency issue is resolved
        ];
    };
  };

  # Seed Antigravity configuration as mutable files so edits in GUI/extensions work
  home.activation.setupAntigravityConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for user_dir in "${config.home.homeDirectory}/.antigravity-ide/User" "${config.home.homeDirectory}/.config/Antigravity IDE/User"; do
      mkdir -p "$user_dir"
      
      # Convert symlink to mutable copy or seed from commonData
      if [ -L "$user_dir/settings.json" ]; then
        target=$(readlink -f "$user_dir/settings.json" 2>/dev/null || true)
        rm -f "$user_dir/settings.json"
        if [ -n "$target" ] && [ -f "$target" ]; then
          cp -f "$target" "$user_dir/settings.json"
        else
          cp -f "${antigravitySettingsJson}" "$user_dir/settings.json"
        fi
        chmod 644 "$user_dir/settings.json"
      elif [ ! -f "$user_dir/settings.json" ]; then
        cp -f "${antigravitySettingsJson}" "$user_dir/settings.json"
        chmod 644 "$user_dir/settings.json"
      fi

      if [ -L "$user_dir/keybindings.json" ]; then
        target=$(readlink -f "$user_dir/keybindings.json" 2>/dev/null || true)
        rm -f "$user_dir/keybindings.json"
        if [ -n "$target" ] && [ -f "$target" ]; then
          cp -f "$target" "$user_dir/keybindings.json"
        else
          cp -f "${antigravityKeybindingsJson}" "$user_dir/keybindings.json"
        fi
        chmod 644 "$user_dir/keybindings.json"
      elif [ ! -f "$user_dir/keybindings.json" ]; then
        cp -f "${antigravityKeybindingsJson}" "$user_dir/keybindings.json"
        chmod 644 "$user_dir/keybindings.json"
      fi
    done
  '';
}
