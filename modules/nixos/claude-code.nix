{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.claudeCode;
  json = pkgs.formats.json { };
in
{
  # Managed settings (permission and auto-mode rules) rank above user and
  # project settings, but their lists merge, so "always allow" rules saved
  # elsewhere still add on top. Preferences stay in ~/.claude/settings.json
  # (home-manager ai-agents.nix, claude.settings).
  options.my.claudeCode = {
    enable = lib.mkEnableOption "the fleet's Claude Code managed settings";

    settings = lib.mkOption {
      inherit (json) type;
      default = { };
      example = {
        permissions.allow = [ "Bash(netbird status)" ];
      };
      description = ''
        Managed settings, merged across modules: a module that brings a
        service can add the rules for its CLI here. Lists are concatenated.
        The fleet policy (files/claude-code-policy.json) is always included.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    my.claudeCode.settings = lib.importJSON ./files/claude-code-policy.json;

    environment.etc."claude-code/managed-settings.d/10-kleinbem.json".source =
      json.generate "claude-code-managed-settings.json" cfg.settings;
  };
}
