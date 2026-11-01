{
  config,
  lib,
  pkgs,
  ...
}:
# External dead-man's switch (healthchecks.io). Local alerting lives on core-pi
# or the watched host, so a dead host goes silent; missing pings alert from
# outside the fleet instead. Pings: <host>-alive every 5 min, and
# <host>-backup-<job> after each backup job.
#
# my.heartbeat.checks feeds nix/infra/healthchecks.tf via infra/heartbeats.json
# (slug = check name). Only for always-on hosts: the alive check alerts on any gap.
let
  cfg = config.my.heartbeat;
  host = config.networking.hostName;
  keyFile = config.sops.secrets.healthchecks_ping_key.path;

  pingAlive = pkgs.writeShellScript "heartbeat-alive" ''
    set -u
    key=$(${pkgs.coreutils}/bin/tr -d '[:space:]' < ${keyFile}) || exit 0
    [ -n "$key" ] || exit 0
    exec ${pkgs.curl}/bin/curl -fsS -m 10 --retry 3 -o /dev/null "${cfg.baseUrl}/$key/${host}-alive"
  '';

  checkType = lib.types.submodule {
    options = {
      kind = lib.mkOption {
        type = lib.types.enum [
          "alive"
          "backup"
        ];
      };
      timeout = lib.mkOption {
        type = lib.types.ints.positive;
        description = "Expected ping period, seconds.";
      };
      grace = lib.mkOption {
        type = lib.types.ints.positive;
        description = "Extra slack before alerting, seconds.";
      };
    };
  };
in
{
  options.my.heartbeat = {
    enable = lib.mkEnableOption "external dead-man's-switch pings (healthchecks.io)";
    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://hc-ping.com";
    };
    checks = lib.mkOption {
      type = lib.types.attrsOf checkType;
      readOnly = true;
      description = "Checks this host pings, keyed by slug — consumed by nix/infra/healthchecks.tf.";
    };
  };

  config = lib.mkMerge [
    {
      my.heartbeat.checks = lib.optionalAttrs cfg.enable (
        {
          "${host}-alive" = {
            kind = "alive";
            timeout = 300; # timer below pings every 5 min
            # Must outlast a router firmware update (WAN down 15+ min).
            grace = 1800;
          };
        }
        // lib.listToAttrs (
          map (
            job:
            lib.nameValuePair "${host}-backup-${job}" {
              kind = "backup";
              timeout = 86400; # daily timers
              grace = 6 * 3600; # RandomizedDelaySec + slow Drive uploads
            }
          ) config.my.backup.jobs
        )
      );
    }

    (lib.mkIf cfg.enable {
      sops.secrets.healthchecks_ping_key = { };

      systemd.services.heartbeat-alive = {
        description = "External alive ping (healthchecks.io)";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig.Type = "oneshot";
        serviceConfig.ExecStart = pingAlive;
      };
      systemd.timers.heartbeat-alive = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
        };
      };

      # Backup jobs ping the same project (nix-presets backup-engine).
      my.backup.heartbeat = {
        pingKeyFile = keyFile;
        inherit (cfg) baseUrl;
      };
    })
  ];
}
