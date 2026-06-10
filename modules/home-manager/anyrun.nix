{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.modules.anyrun;
in
{
  options.modules.anyrun = {
    enable = lib.mkEnableOption "Anyrun launcher";
  };

  config = lib.mkIf cfg.enable {
    programs.anyrun = {
      enable = true;
      config = {
        plugins = with inputs.anyrun.packages.${pkgs.stdenv.hostPlatform.system}; [
          applications
          dictionary
          rink
          shell
          symbols
          translate
          websearch
        ];
        width.fraction = 0.3;
        y.fraction = 0.3;
        hideIcons = false;
        ignoreExclusiveZones = false;
        layer = "overlay";
        hidePluginInfo = false;
        closeOnClick = true;
        showResultsImmediately = false;
        maxEntries = null;
      };

      # Basic styling to match COSMIC/Dark theme
      extraCss = ''
        window {
          background: rgba(0, 0, 0, 0);
        }

        #main {
          background: #1e1e2e;
          border-radius: 16px;
          padding: 8px;
          border: 1px solid #313244;
        }

        #entry {
          background: #313244;
          color: #cdd6f4;
          border-radius: 8px;
          margin-bottom: 8px;
          padding: 8px;
        }

        #match.selected {
          background: #45475a;
          border-radius: 8px;
        }
      '';

      extraConfigFiles."applications.ron".text = ''
        Config(
          desktop_actions: true,
          max_entries: 5,
          terminal: Some("ptyxis"),
        )
      '';
    };
  };
}
