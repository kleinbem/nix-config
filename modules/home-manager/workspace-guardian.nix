{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.modules.workspace-guardian = {
    enable = lib.mkEnableOption "ATLAS workspace guardian (journal health watcher + container self-heal)";
  };

  config = lib.mkIf config.modules.workspace-guardian.enable {
    # Replaces the hand-dropped unit that used to live in
    # ~/.config/systemd/user/workspace-guardian.service. The binary calls
    # tools/ai-logs.sh inside the meta workspace checkout at runtime, so it
    # only makes sense on the workstation where that checkout exists.
    systemd.user.services.workspace-guardian = {
      Unit = {
        Description = "ATLAS Infrastructure AI - Autonomous Guardian";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = lib.getExe pkgs.workspace-guardian;
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
