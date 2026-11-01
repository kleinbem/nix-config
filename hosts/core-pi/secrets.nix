{
  inputs,
  config,
  lib,
  secretFile,
  myInventory,
  ...
}:
let
  mkPerContainerSecrets = import ../../lib/secrets.nix { inherit lib inputs; };

  # ntfy server auth (nix/per-host/core-pi.yaml): ntfy_auth_users,
  # ntfy_auth_access, ntfy_auth_tokens in ntfy's declarative formats (see
  # nix-presets containers/ntfy.nix secretsFile). All three gated on the
  # plaintext key names so eval works before the values exist; once they
  # do, the rendered env file flips the server to deny-all.
  hostSops = secretFile "nix/per-host/core-pi.yaml";
  hasKey =
    k: builtins.pathExists hostSops && lib.hasInfix "\n${k}:" ("\n" + builtins.readFile hostSops);
  hasNtfyAuth = lib.all hasKey [
    "ntfy_auth_users"
    "ntfy_auth_access"
    "ntfy_auth_tokens"
  ];
  ntfyAuthSecret = lib.mkIf hasNtfyAuth { sopsFile = hostSops; };

  # Caddy's Cloudflare DNS-01 token for inventory nodes with
  # `publicCert = true` (minted + synced by nix/infra/r2-tokens); asserted
  # below so a missing token fails the eval, not Caddy.
  acmeDns = lib.any (n: n.publicCert or false) (lib.attrValues myInventory.network.nodes);
in
{
  # Without the token Caddy can't get the certificate, and an unset
  # {env.CLOUDFLARE_API_TOKEN} may keep it from loading the config at all,
  # taking every vhost down. Fail the eval instead: run `just apply` in
  # nix/infra/r2-tokens and bump kleinbem-secrets first.
  assertions = [
    {
      assertion = acmeDns -> hasKey "caddy_acme_cloudflare_token";
      message = "inventory has a node with publicCert = true, but kleinbem-secrets/nix/per-host/core-pi.yaml has no caddy_acme_cloudflare_token (mint it: nix/infra/r2-tokens `just apply`).";
    }
  ];

  sops = {
    secrets =
      # defaultSopsFile/defaultSopsFormat/validateSopsFiles are set fleet-wide
      # in modules/nixos/base.nix.
      {
        # Vaultwarden — Argon2 PHC hash for the /admin page (ADMIN_TOKEN).
        # Generate: `nix run nixpkgs#vaultwarden -- hash --preset owasp`.
        # Add the value to kleinbem-secrets/nix/shared.yaml (defaultSopsFile).
        # validateSopsFiles = false here, so eval passes before the key exists;
        # activation (sops-install-secrets) needs it present.
        vaultwarden_admin_token = { };
      }
      // (
        # Authentik, the shared IdP. Per-container file scoped to core_pi.
        # Social login sources are configured inside Authentik, not here.
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
        # Ente Auth (auth.kleinbem.dev). minio_root_password only applies on
        # MinIO's first boot: on a live deployment rotate the root user with
        # `mc admin user` BEFORE restarting museum, or it loses object storage.
        # No postgres_password: ente uses native Postgres with peer auth.
        mkPerContainerSecrets {
          container = "ente";
          keys = [
            "minio_root_password"
            "jwt_secret"
          ];
        }
      )
      // {
        # Same ente scope, separate file so adding them needed no YubiKey
        # re-encrypt of the main one. museum requires key.encryption and key.hash.
        ente_key_encryption = {
          sopsFile = secretFile "nix/per-container/ente-keys.yaml";
        };
        ente_key_hash = {
          sopsFile = secretFile "nix/per-container/ente-keys.yaml";
        };
      }
      // {
        # Attic Binary Cache
        attic_server_token_rs256 = {
          sopsFile = secretFile "nix/per-host/core-pi.yaml";
        };
        # Read-only pull token — activates modules/nixos/attic-pull.nix (netrc
        # Bearer auth + NetBird routing). Without it the host gets 401 from the
        # private cache and the nightly upgrade rebuilds the linux-rpi kernel
        # on-device until RuntimeMaxSec kills it.
        attic_pull_token = { };

        # Included into nix.conf by modules/nixos/core.nix so the daemon can
        # fetch the private kleinbem-secrets repo during upgrades;
        # unauthenticated archive fetches of a private repo always 404.
        github_read_all_token = {
          mode = "0440";
          group = "wheel";
        };

        # Secret ntfy topic — arms the nixos-upgrade-listener (rpi5-node.nix
        # enables it; ConditionPathExists on this secret's path keeps it inert
        # until the key materialises at activation).
        ntfy_deploy_topic = { };

        # ntfy server: declarative users / ACLs / tokens (see hasNtfyAuth).
        ntfy_auth_users = ntfyAuthSecret;
        ntfy_auth_access = ntfyAuthSecret;
        ntfy_auth_tokens = ntfyAuthSecret;

        # Caddy DNS-01 (see acmeDns).
        caddy_acme_cloudflare_token = lib.mkIf acmeDns { sopsFile = hostSops; };

        # NetBird — consumed by modules/nixos/networking.nix → netbird-autojoin
        # oneshot (`netbird up --setup-key` when the daemon reports NeedsLogin).
        # Only helps fresh enrollments: a registered peer whose SSO login
        # expired refuses setup-key re-auth, so infra/netbird/peers.tf disables
        # login expiration for core-pi instead.
        netbird_setup_key = { };

        # Cloudflare Tunnel
        cloudflare_account_id = {
          sopsFile = secretFile "nix/per-host/core-pi.yaml";
        };
        cloudflare_tunnel_id = {
          sopsFile = secretFile "nix/per-host/core-pi.yaml";
        };
        cloudflare_tunnel_secret = {
          sopsFile = secretFile "nix/per-host/core-pi.yaml";
        };
      };

    templates = {
      # Bind-mounted into the ntfy container as /run/secrets/ntfy.env and
      # loaded as its EnvironmentFile (my.containers.ntfy.secretsFile).
      "ntfy.env" = lib.mkIf hasNtfyAuth {
        mode = "0444";
        content = ''
          NTFY_AUTH_USERS=${config.sops.placeholder.ntfy_auth_users}
          NTFY_AUTH_ACCESS=${config.sops.placeholder.ntfy_auth_access}
          NTFY_AUTH_TOKENS=${config.sops.placeholder.ntfy_auth_tokens}
        '';
      };
      # Bind-mounted into the caddy container as /run/secrets/caddy.env
      # (my.containers.caddy.secretsFile).
      "caddy.env" = lib.mkIf acmeDns {
        mode = "0444";
        content = ''
          CLOUDFLARE_API_TOKEN=${config.sops.placeholder.caddy_acme_cloudflare_token}
        '';
      };
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
