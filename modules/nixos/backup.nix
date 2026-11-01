{
  inputs,
  config,
  lib,
  pkgs,
  secretFile,
  ...
}:
# Fleet wiring for nix-presets' backup-engine: where backups go and with which
# keys. Data owners register what goes via my.backup.items.
#
#   r2      required. `secure/` is bucket-locked 30d so a compromised host
#           can't erase its recent history.
#   gdrive  second provider, best-effort; pruned here (Drive has no lifecycle).
#
# Needs backup_r2_rclone_config per host (revocable alone) plus rclone_config,
# restic_password and ntfy_alert_topic in nix/shared.yaml. Alerts never go to
# ntfy_deploy_topic: any message there starts an upgrade on every host.
# Restore: see backup-engine's header; secure bundles decrypt with either YubiKey.
let
  cfg = config.my.backup;
  keys = import ./keys.nix;
  host = config.networking.hostName;

  # ntfy_alert_token (nix/shared.yaml): write token on the alert topic once
  # ntfy runs with auth. Gated on the plaintext key name so eval works
  # before the value exists; sops-nix fails activation on a missing key.
  sharedSops = secretFile "nix/shared.yaml";
  hasAlertToken =
    builtins.pathExists sharedSops
    && lib.hasInfix "\nntfy_alert_token:" ("\n" + builtins.readFile sharedSops);
  alertTokenPath = "/run/secrets/ntfy_alert_token";

  notify = pkgs.writeShellScript "backup-notify-ntfy" ''
    set -u
    prio="$1"; title="$2"; shift 2
    ${pkgs.util-linux}/bin/logger -t backup "$title: $*"
    topic="$(cat ${config.sops.secrets.ntfy_alert_topic.path} 2>/dev/null || true)"
    [ -n "$topic" ] || exit 0
    auth=()
    if [ -r ${alertTokenPath} ]; then
      auth=(-H "Authorization: Bearer $(cat ${alertTokenPath})")
    fi
    ${pkgs.curl}/bin/curl -fsS --max-time 15 "''${auth[@]}" \
      -H "Title: $title" -H "Priority: $prio" -H "Tags: floppy_disk" \
      -d "$*" "https://ntfy.kleinbem.dev/$topic" >/dev/null || true
  '';
in
{
  imports = [ inputs.nix-presets.nixosModules.backup-engine ];

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      backup_r2_rclone_config.sopsFile = secretFile "nix/per-host/${host}.yaml";
      rclone_config = { };
      restic_password = { };
      ntfy_alert_topic = { };
      ntfy_alert_token = lib.mkIf hasAlertToken { };
    };

    my.backup = {
      destinations = {
        r2 = {
          remote = "r2:kleinbem-backup";
          rcloneConfigFile = config.sops.secrets.backup_r2_rclone_config.path;
        };
        gdrive = {
          # Own OAuth client with drive.file scope, which only sees files it
          # created, hence its own top-level folder. The old `gdrive:` remote in
          # rclone_config is still used by nasbook's legacy backup container.
          remote = "gdrive-fleet:kleinbem-backups";
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
