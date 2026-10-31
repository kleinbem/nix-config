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
  # Claude Code's managed settings: the policy part of its config (permission
  # rules, auto-mode rules, default mode). Claude Code reads every file in
  # /etc/claude-code/managed-settings.d/ above all user and project settings,
  # and combines their lists with the lower scopes', so rules saved from an
  # "always allow" in ~/.claude or a repo still add on top. Preferences
  # (theme, model, hooks) stay in ~/.claude/settings.json, which Claude Code
  # writes itself; see modules.ai-agents.claude.settings in home-manager.
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
