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
      # Identity (Authelia) — all 4 secrets live in one per-container file,
      # scoped to core_pi in kleinbem-secrets/.sops.yaml (only the host that
      # actually runs the container can decrypt them). The 3 crypto secrets
      # used to live in shared.yaml (decryptable by every fleet host) before
      # this consolidation — that was a legacy artifact predating the
      # per-container convention (see kleinbem-auth.yaml/stalwart.yaml), not
      # a deliberate choice, so they moved here alongside the seed users.yml.
      mkPerContainerSecrets {
        container = "authelia";
        keys = [
          "session_secret"
          "jwt_secret"
          "storage_encryption_key"
          "users_file"
        ];
      }
      // {
        # Vaultwarden — Argon2 PHC hash for the /admin page (ADMIN_TOKEN).
        # Generate: `nix run nixpkgs#vaultwarden -- hash --preset owasp`.
        # Add the value to kleinbem-secrets/nix/shared.yaml (defaultSopsFile).
        # validateSopsFiles = false here, so eval passes before the key exists;
        # activation (sops-install-secrets) needs it present.
        vaultwarden_admin_token = { };
      }
      // (
        # kleinbem-auth (better-auth login for kleinbem.dev). Per-container
        # file, scoped to core_pi in kleinbem-secrets/.sops.yaml.
        # better_auth_secret is populated; google_/facebook_ are empty until
        # the OAuth apps exist — the service starts fine with no providers
        # (see nix-presets preset). fullKey = false: this file's own YAML
        # keys are the bare suffix (e.g. "better_auth_secret"), unlike
        # authelia/authentik's full-attr-name convention below.
        mkPerContainerSecrets {
          container = "kleinbem-auth";
          fullKey = false;
          keys = [
            "better_auth_secret"
            "google_client_id"
            "google_client_secret"
            "facebook_client_id"
            "facebook_client_secret"
            "github_client_id"
            "github_client_secret"
            "linkedin_client_id"
            "linkedin_client_secret"
            "microsoft_client_id"
            "microsoft_client_secret"
          ];
        }
        // {
          kleinbem_auth_turnstile_secret = {
            sopsFile = "${inputs.kleinbem-secrets}/nix/per-container/kleinbem-auth.yaml";
            key = "turnstile_secret_key";
          };
        }
      )
      // (
        # Authentik — shared IdP replacing kleinbem-auth. Per-container file,
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
