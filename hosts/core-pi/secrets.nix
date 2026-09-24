{
  inputs,
  config,
  lib,
  ...
}:
let
  mkPerContainerSecrets = import ../../lib/secrets.nix { inherit lib inputs; };
in
{
  sops = {
    # defaultSopsFile/defaultSopsFormat/validateSopsFiles now default
    # fleet-wide in modules/nixos/base.nix.
    secrets =
      # Authelia decommissioned 2026-09-22 — all 6 services it protected
      # migrated to Authentik forward-auth (nix/infra/authentik.tf's
      # fleet_forward_auth Provider); its own 4 secrets
      # (session_secret/jwt_secret/storage_encryption_key/users_file, in
      # kleinbem-secrets/nix/per-container/authelia.yaml) are no longer
      # referenced anywhere and were removed from here.
      {
        # Vaultwarden — Argon2 PHC hash for the /admin page (ADMIN_TOKEN).
        # Generate: `nix run nixpkgs#vaultwarden -- hash --preset owasp`.
        # Add the value to kleinbem-secrets/nix/shared.yaml (defaultSopsFile).
        # validateSopsFiles = false here, so eval passes before the key exists;
        # activation (sops-install-secrets) needs it present.
        vaultwarden_admin_token = { };
      }
      // (
        # Authentik — shared IdP, replaces kleinbem-auth (decommissioned
        # 2026-09-21). Per-container file,
        # scoped to core_pi in kleinbem-secrets/.sops.yaml. All 4 values are
        # freshly generated internal secrets (no external OAuth app needed
        # for these) — social login sources are configured inside Authentik
        # itself once its own OAuth apps exist, not via NixOS secrets.
        mkPerContainerSecrets {
          container = "authentik";
          keys = [
            "secret_key"
            "postgres_password"
            "bootstrap_admin_password"
            "bootstrap_api_token"
          ];
        }
      )
      // (
        # Ente Auth (2FA/TOTP vault, auth.kleinbem.dev) — freshly generated
        # 2026-09-23, replacing the hardcoded "pgpass"/"password123"/
        # placeholder-JWT that used to live directly in ente.nix. Per-
        # container file, scoped to core_pi in kleinbem-secrets/.sops.yaml.
        # postgres_password/minio_root_password only take effect on each
        # service's own first start (initdb / MinIO's first boot) — an
        # already-initialized live deployment needs its running Postgres
        # user and MinIO root user rotated to match via `ALTER USER` /
        # `mc admin user` BEFORE restarting museum with the new config,
        # or the app loses its DB/object-storage connection.
        mkPerContainerSecrets {
          container = "ente";
          keys = [
            "postgres_password"
            "minio_root_password"
            "jwt_secret"
          ];
        }
      )
      // {
        # Same ente scope, separate file (nix/per-container/ente-keys.yaml)
        # — added 2026-09-24 when museum got repackaged as a native service,
        # after ente.yaml above already existed as ciphertext (adding a key
        # to an existing sops file needs a YubiKey touch this session
        # didn't have). key.encryption/key.hash: required by museum's real
        # config schema, discovered while packaging it from source — the
        # original hand-written museum.yaml never set them at all.
        ente_key_encryption = {
          sopsFile = "${inputs.kleinbem-secrets}/nix/per-container/ente-keys.yaml";
        };
        ente_key_hash = {
          sopsFile = "${inputs.kleinbem-secrets}/nix/per-container/ente-keys.yaml";
        };
      }
      // {
        # Attic Binary Cache
        attic_server_token_rs256 = {
          sopsFile = "${inputs.kleinbem-secrets}/nix/per-host/core-pi.yaml";
        };
        # Read-only pull token — activates modules/nixos/attic-pull.nix (netrc
        # Bearer auth + NetBird routing). Without it the host gets 401 from the
        # private cache and the nightly upgrade rebuilds the linux-rpi kernel
        # on-device until RuntimeMaxSec kills it.
        attic_pull_token = { };

        # Wires into nix.conf via modules/nixos/core.nix's include directive
        # (gated on this secret existing) so the nix daemon can authenticate
        # GitHub fetches of the private kleinbem-secrets repo — needed
        # whenever autoUpgrade needs a kleinbem-secrets commit not already
        # sitting in the local store. nixos-nvme/orin-nano already had this;
        # mac-mini/core-pi/hass-pi didn't (found via nasbook hitting exactly
        # this failure 2026-09-20: unauthenticated archive fetches of a
        # private repo 404 unconditionally, regardless of commit).
        github_read_all_token = {
          mode = "0440";
          group = "wheel";
        };

        # Secret ntfy topic — arms the nixos-upgrade-listener (rpi5-node.nix
        # enables it; ConditionPathExists on this secret's path keeps it inert
        # until the key materialises at activation).
        ntfy_deploy_topic = { };

        # NetBird — consumed by modules/nixos/networking.nix → netbird-autojoin
        # oneshot (`netbird up --setup-key` when the daemon reports NeedsLogin).
        # Safety net for FRESH enrollments only (reinstall / wiped
        # /var/lib/netbird): an already-registered peer whose SSO login expired
        # REFUSES setup-key re-auth (verified 2026-07-05). That case is prevented
        # instead by infra/netbird/peers.tf disabling login expiration for core-pi.
        netbird_setup_key = { };

        # Cloudflare Tunnel
        cloudflare_account_id = {
          sopsFile = "${inputs.kleinbem-secrets}/nix/per-host/core-pi.yaml";
        };
        cloudflare_tunnel_id = {
          sopsFile = "${inputs.kleinbem-secrets}/nix/per-host/core-pi.yaml";
        };
        cloudflare_tunnel_secret = {
          sopsFile = "${inputs.kleinbem-secrets}/nix/per-host/core-pi.yaml";
        };
      };

    templates = {
      "attic.env" = {
        mode = "0444";
        content = ''
          ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="${config.sops.placeholder.attic_server_token_rs256}"
        '';
      };
      "cloudflare-tunnel-credentials.json" = {
        mode = "0444";
        content = ''
          {
            "AccountTag": "${config.sops.placeholder.cloudflare_account_id}",
            "TunnelID": "${config.sops.placeholder.cloudflare_tunnel_id}",
            "TunnelName": "core-pi",
            "TunnelSecret": "${config.sops.placeholder.cloudflare_tunnel_secret}"
          }
        '';
      };
    };
  };
}
