{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
# Fleet wiring for nix-presets' backup-engine: WHERE backups go and with
# which keys. WHAT goes is registered by the data owners themselves
# (presets + modules set my.backup.items); a host only flips
# `my.backup.enable = true` and adds any host-only paths.
#
#   r2      kleinbem-backup bucket (nix/infra/cloudflare-r2.tf). Required.
#           `secure/` is bucket-LOCKED 30d → a compromised host can't erase
#           its own recent secure history; expired after 365d by lifecycle.
#   gdrive  second provider (covers losing R2 / the Cloudflare account).
#           Best-effort for the secure tier, pruned after 365d here since
#           Drive has no lifecycle rules.
#
# Layout per destination: <remote>/secure/<host>/<host>-<ts>.tar.gz.age
#                         <remote>/restic/<host>   (restic repo)
#
# Secrets a host needs before enabling (all sops):
#   nix/per-host/<host>.yaml  backup_r2_rclone_config  — per host so a
#                             single host's R2 token can be revoked alone
#   nix/shared.yaml           rclone_config (gdrive), restic_password,
#                             ntfy_alert_topic
#
# Alerts go to ntfy_alert_topic — the fleet's single human-facing alert
# topic, shared with CI (distributed as the NTFY_ALERT_TOPIC Actions secret
# by nix/infra/github-secrets.tf from the same shared.yaml key). NEVER
# ntfy_deploy_topic: every host's nixos-upgrade-listener starts an upgrade on
# ANY message there.
#
# Restore: see nix-presets/nixosModules/backup-engine (header) and
# docs in hosts that enable it; secure bundles decrypt with either YubiKey.
let
  cfg = config.my.backup;
  keys = import ./keys.nix;
  host = config.networking.hostName;

  notify = pkgs.writeShellScript "backup-notify-ntfy" ''
    set -u
    prio="$1"; title="$2"; shift 2
    ${pkgs.util-linux}/bin/logger -t backup "$title: $*"
    topic="$(cat ${config.sops.secrets.ntfy_alert_topic.path} 2>/dev/null || true)"
    [ -n "$topic" ] || exit 0
    ${pkgs.curl}/bin/curl -fsS --max-time 15 \
      -H "Title: $title" -H "Priority: $prio" -H "Tags: floppy_disk" \
      -d "$*" "https://ntfy.kleinbem.dev/$topic" >/dev/null || true
  '';
in
{
  imports = [ inputs.nix-presets.nixosModules.backup-engine ];

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      backup_r2_rclone_config.sopsFile = "${inputs.kleinbem-secrets}/nix/per-host/${host}.yaml";
      rclone_config = { };
      restic_password = { };
      ntfy_alert_topic = { };
    };

    my.backup = {
      destinations = {
        r2 = {
          remote = "r2:kleinbem-backup";
          rcloneConfigFile = config.sops.secrets.backup_r2_rclone_config.path;
        };
        gdrive = {
          remote = "gdrive:backups";
          rcloneConfigFile = config.sops.secrets.rclone_config.path;
          required = false;
          pruneSecureAfterDays = 365;
          # Drive rate-limits hard; same tuning as the legacy backup
          # container. Embedded quotes are required (systemd word-splits
          # ExecStart, and rclone.args REPLACES restic's default verb).
          resticExtraOptions = [
            "rclone.args=\"serve restic --stdio --tpslimit 5 --fast-list --drive-chunk-size 64M\""
          ];
        };
      };

      secure.recipients = [
        keys.age.yubikey-primary
        keys.age.yubikey-backup
      ];
      bulk.passwordFile = config.sops.secrets.restic_password.path;
      notify.command = toString notify;
    };
  };
}
