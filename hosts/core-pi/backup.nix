# core-pi — off-site backup for the identity/vault cluster.
#
# Split design (see the long discussion 2026-09-06/07):
#
#   * VAULT  — Vaultwarden is small (MBs) and uniquely catastrophic to lose, so
#     it gets a dedicated, dependency-light path: consistent sqlite `.backup`
#     → tar → `age` (encrypt to both YubiKey recipients) → `rclone copyto` to
#     TWO destinations. Restore needs only a YubiKey + `age` + `tar` — no
#     restic, no repo password, no running Vaultwarden. R2 is the must-succeed
#     leg; gdrive is best-effort second copy. Objects are date-stamped and
#     core-pi is never given delete rights on the R2 bucket, so a full core-pi
#     compromise cannot erase backup history (belt: enable R2 Object Lock,
#     30d, when you create the bucket).
#
#   * BULK   — Ente + kleinbem-auth are larger / lower-stakes. Plain restic
#     (dedup + retention) → R2. Ente's Postgres is backed up as a raw datadir
#     for now (restore leans on PG crash recovery); a `machinectl`-based
#     pg_dump prepare step is a follow-up.
#
# Why not the `backup` container preset: core-pi doesn't import it, and it
# bakes `cfg.targets` into the per-*name* container closure
# ([[project_fleet_standalone_containers_adr002]]) — the name `backup` already
# belongs to nasbook's target set. A host systemd service sidesteps that.
# (nasbook's `backup` container is also a dead offline sops placeholder since
# 2026-08-06 — do not depend on it.)
#
# ─── ENABLING — full runbook (deploy stays green until step 4) ───────────────
#  0. Bucket: `nix/infra/cloudflare-r2.tf` creates `kleinbem-backup` on the next
#     `bash nix/tools/tf-apply.sh` (YubiKey #1).
#  1. R2 token: dashboard → R2 → "Manage R2 API Tokens" → Create, permission
#     "Object Read & Write", scope to `kleinbem-backup`. Copy the Access Key ID,
#     Secret Access Key, and the S3 endpoint it shows.
#  2. `sops kleinbem-secrets/nix/per-host/core-pi.yaml` (YubiKey #2) — add:
#       restic_password: <output of `openssl rand -base64 32`>
#       backup_rclone_config: |
#         [r2]
#         type = s3
#         provider = Cloudflare
#         access_key_id = <from step 1>
#         secret_access_key = <from step 1>
#         endpoint = <from step 1, e.g. https://<acct>.r2.cloudflarestorage.com>
#         acl = private
#         no_check_bucket = true
#     `[gdrive]` is OPTIONAL — add it later (its own `type = drive` block); the
#     vault job's gdrive leg is best-effort and just warns if the remote is
#     absent. R2 alone is enough to turn this on.
#  3. `git add hosts/core-pi/backup.nix` (flake eval can't see it until tracked),
#     flip `enable = true` below.
#  4. Deploy core-pi. Then `systemctl start backup-vault.service` and confirm an
#     object in `r2:kleinbem-backup/vault/`; let `restic-backups-bulk` run and
#     check `restic snapshots`.
#  5. RESTORE TEST before retiring parallel-run Bitwarden: fetch the latest
#     vault-*.tar.gz.age, `age -d` (YubiKey), `tar xzf`, then
#     `sqlite3 db.sqlite3 'select count(*) from users;'`.
#  6. Pruning: vault objects on R2 are tiny — leave them / prune from your
#     laptop, never core-pi. `restic-backups-bulk` prunes itself on-box.
{
  config,
  lib,
  pkgs,
  inputs,
  myInventory,
  ...
}:
let
  # ⇩ flip to true once backup_rclone_config + restic_password exist in
  #   kleinbem-secrets/nix/per-host/core-pi.yaml (see header).
  enable = false;

  # Public age recipients — both YubiKeys, matching every sops file in the
  # fleet (kleinbem-secrets/.sops.yaml `keys:` block). Restore therefore needs
  # a YubiKey, same posture as the rest of the secret tree.
  ageRecipients = [
    "age1yubikey1q2lhmqc0h6verf025hn62tkjkz25d760h54pdej7a55q4m2hszm8kwssfn0" # martin_primary
    "age1yubikey1qg379rzgajvstx6vhk2fsvc0eu9zyjjk7q24pd3pf5dq22xvlqew23e08l2" # martin_backup
  ];

  stateDir = "/var/lib/backup-state";
  ntfyBase = "http://${myInventory.network.nodes.ntfy.ip}";

  # Common toolchain for the units below.
  toolPkgs = [
    pkgs.coreutils
    pkgs.gnutar
    pkgs.gzip
    pkgs.rsync
    pkgs.sqlite
    pkgs.age
    pkgs.rclone
    pkgs.restic
    pkgs.curl
  ];

  # Best-effort ntfy notify — reuses the existing core-pi deploy topic
  # (ntfy_deploy_topic, already declared in secrets.nix). A dedicated topic
  # would be cleaner; not worth another secret for now.
  notify = pkgs.writeShellScript "backup-notify" ''
    set -u
    prio="''${1:-default}"; title="''${2:-core-pi backup}"; shift 2 || true
    topic="$(cat ${config.sops.secrets.ntfy_deploy_topic.path} 2>/dev/null || true)"
    [ -n "$topic" ] || exit 0
    ${pkgs.curl}/bin/curl -fsS --max-time 10 \
      -H "Title: $title" -H "Priority: $prio" \
      -d "$*" "${ntfyBase}/$topic" >/dev/null || true
  '';
in
lib.mkIf enable {
  sops.secrets = {
    restic_password = {
      sopsFile = "${inputs.nix-secrets}/nix/per-host/core-pi.yaml";
    };
    backup_rclone_config = {
      sopsFile = "${inputs.nix-secrets}/nix/per-host/core-pi.yaml";
    };
  };

  # ─── BULK: restic of the larger, lower-stakes state → R2 ───────────────────
  services.restic.backups.bulk = {
    initialize = true;
    repository = "rclone:r2:kleinbem-backup/restic";
    passwordFile = config.sops.secrets.restic_password.path;
    rcloneConfigFile = config.sops.secrets.backup_rclone_config.path;
    paths = [
      "/var/lib/ente" # raw PG datadir — pg_dump prepare step is a follow-up
      "/var/lib/kleinbem-auth"
    ];
    exclude = [
      "/var/lib/ente/**/tmp"
      "/var/lib/*/*.sqlite3-wal"
      "/var/lib/*/*.sqlite3-shm"
    ];
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
    timerConfig = {
      OnCalendar = "*-*-* 03:15:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d ${stateDir} 0700 root root - -"
    ];

    services = {
      # ─── VAULT: consistent dump → age → two off-sites ──────────────────────
      backup-vault = {
        description = "Encrypted off-site backup of Vaultwarden (age → R2 + gdrive)";
        onFailure = [ "backup-notify-failure@backup-vault.service" ];
        path = toolPkgs;
        serviceConfig = {
          Type = "oneshot";
          # `full` (not `strict`): leaves /var + /root writable so rclone's config
          # cache doesn't trip; still protects /usr /boot /etc. Runs as root — it
          # has to read the container's root-owned data dir.
          ProtectSystem = "full";
          PrivateTmp = true;
        };
        script = ''
          set -euo pipefail
          umask 077
          src=/var/lib/vaultwarden
          conf=${config.sops.secrets.backup_rclone_config.path}
          ts=$(date -u +%Y%m%dT%H%M%SZ)
          work=$(mktemp -d)
          trap 'rm -rf "$work"' EXIT

          # 1. crash-consistent copy of the live sqlite db (WAL mode → plain .backup)
          install -d -m700 "$work/bundle"
          sqlite3 "$src/db.sqlite3" ".backup '$work/bundle/db.sqlite3'"

          # 2. everything else Vaultwarden persists (rsa keys, attachments, sends,
          #    config.json), minus regenerable caches and the live db files.
          rsync -a \
            --exclude 'db.sqlite3' --exclude 'db.sqlite3-wal' --exclude 'db.sqlite3-shm' \
            --exclude 'icon_cache/' --exclude 'tmp/' \
            "$src"/ "$work/bundle"/

          # 3. single archive, encrypted to both YubiKeys
          tar -C "$work/bundle" -czf "$work/vault.tar.gz" .
          age ${lib.concatMapStringsSep " " (r: "-r ${r}") ageRecipients} \
            -o "$work/vault-$ts.tar.gz.age" "$work/vault.tar.gz"
          sha256sum "$work/vault-$ts.tar.gz.age" | cut -d' ' -f1 > "$work/vault-$ts.sha256"

          # 4a. R2 — MUST succeed
          for f in "vault-$ts.tar.gz.age" "vault-$ts.sha256"; do
            rclone --config "$conf" copyto "$work/$f" "r2:kleinbem-backup/vault/$f"
          done

          # 4b. gdrive — best effort
          for f in "vault-$ts.tar.gz.age" "vault-$ts.sha256"; do
            rclone --config "$conf" copyto "$work/$f" "gdrive:backups/vault/$f" \
              || echo "WARN: gdrive leg failed for $f" >&2
          done

          date -u +%FT%TZ > ${stateDir}/vault.last-success
          echo "vault backup $ts ok ($(du -h "$work/vault-$ts.tar.gz.age" | cut -f1))"
        '';
      };

      # Notify on restic failure too (the NixOS module names the unit restic-backups-<name>).
      "restic-backups-bulk".onFailure = [
        "backup-notify-failure@restic-backups-bulk.service"
      ];

      # ─── Freshness watchdog — catches "the timer silently stopped" (the nasbook
      #     failure mode), not just "a run errored" ─────────────────────────────
      backup-freshness-check = {
        description = "Alert if the newest successful vault backup is stale";
        path = toolPkgs;
        serviceConfig.Type = "oneshot";
        script = ''
          set -uo pipefail
          marker=${stateDir}/vault.last-success
          if [ ! -f "$marker" ]; then
            ${notify} high "core-pi backup" "no vault backup has ever succeeded"
            exit 0
          fi
          age_s=$(( $(date +%s) - $(date -r "$marker" +%s) ))
          if [ "$age_s" -gt 172800 ]; then
            ${notify} high "core-pi backup" \
              "vault backup STALE: last success $(cat "$marker") ($((age_s/3600))h ago)"
          fi
        '';
      };

      # ─── Shared OnFailure notifier ────────────────────────────────────────────
      "backup-notify-failure@" = {
        description = "ntfy alert for failed backup unit %i";
        serviceConfig.Type = "oneshot";
        scriptArgs = "%i";
        script = ''
          ${notify} high "core-pi backup FAILED" "unit $1 failed — check journalctl -u $1"
        '';
      };
    };

    timers.backup-vault = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 02:30:00";
        Persistent = true;
        RandomizedDelaySec = "20m";
      };
    };
    timers.backup-freshness-check = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 08:00:00";
        Persistent = true;
      };
    };
  };
}
