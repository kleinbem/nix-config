# Nix App Center: app store for nixpkgs. Try an app with nix run, keep it in
# the two nix-app-center-*.nix files at the repo root.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.desktop.nixAppCenter;

  settings = pkgs.writeText "nix-app-center-settings.json" (
    builtins.toJSON {
      config_dir = cfg.configDir;
      # The app can't find the hosts itself: they are declared outside flake.nix.
      host = config.networking.hostName;
      apply_command = cfg.applyCommand;
    }
  );
in
{
  imports = [ inputs.nix-app-center.nixosModules.default ];

  options.my.desktop.nixAppCenter = {
    enable = lib.mkEnableOption "Nix App Center (app store for nixpkgs)";
    configDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.my.home}/Develop/github.com/kleinbem/nix-config";
      description = "The nix-config checkout the app reads and writes its kept apps in.";
    };
    applyCommand = lib.mkOption {
      type = lib.types.str;
      # In a terminal: dev::apply asks for sudo itself, which the app can't answer.
      default = "xdg-terminal-exec bash -c 'cd ${cfg.configDir} && direnv exec . just dev::apply; read -r -p \"Enter closes this window. \" _'";
      description = "What the app runs for Apply.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.nix-app-center.enable = true;

    # Merged, not linked: the app writes its own preferences to the same file.
    home-manager.users.${config.my.username}.home.activation.nixAppCenterSettings =
      inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ]
        ''
          f="$HOME/.config/nix-app-center/settings.json"
          if [ -s "$f" ] && ${pkgs.jq}/bin/jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
            tmp=$(mktemp)
            ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$f" ${settings} > "$tmp"
            run install -m644 "$tmp" "$f"
            rm -f "$tmp"
          else
            run install -Dm644 ${settings} "$f"
          fi
        '';
  };
}
