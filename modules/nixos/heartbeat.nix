{
  config,
  lib,
  pkgs,
  ...
}:
# External dead-man's switch (healthchecks.io). Everything *local* that
# alerts — ntfy, gatus, the backup freshness watchdog — runs on core-pi or on
# the host being watched, so a dead core-pi (or a dead host) goes silent
# instead of alerting. Pings go out to healthchecks.io; *missing* pings alert
# from outside the fleet (its own email/phone channels, never ntfy.kleinbem.dev).
#
# Per host, when `my.heartbeat.enable`:
#   <host>-alive              every 5 min (timer)       — host/network is up
#   <host>-backup-<job>       after each backup job     — via the backup engine
#                             (…/fail from its OnFailure unit)
#
# `my.heartbeat.checks` lists exactly those slugs with their expected period;
# nix-config's flake output `heartbeats` projects it for nix/infra, whose
# healthchecks.tf creates one check per slug (data bridge: infra/heartbeats.json,
# written by nix/tools/gen-iac-data.sh). Slugs are the check names — the
# healthchecks API derives the slug from the name.
#
# Secret: `healthchecks_ping_key` (the project ping key) in nix/shared.yaml.
# Only enable on always-on hosts — the alive check alerts on any gap.
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
            grace = 900;
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
