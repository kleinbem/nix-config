{ inputs, config, ... }:
{
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/nix/shared.yaml";
    defaultSopsFormat = "yaml";
    validateSopsFiles = false;

    secrets = {
      # Identity (Authelia)
      authelia_session_secret = { };
      authelia_jwt_secret = { };
      authelia_storage_encryption_key = { };
      # Real seed users.yml (argon2id-hashed accounts) -- per-container, not
      # shared.yaml, since it's genuinely unique to this one container.
      authelia_users_file = {
        sopsFile = "${inputs.nix-secrets}/nix/per-container/authelia.yaml";
      };

      # Vaultwarden — Argon2 PHC hash for the /admin page (ADMIN_TOKEN).
      # Generate: `nix run nixpkgs#vaultwarden -- hash --preset owasp`.
      # Add the value to kleinbem-secrets/nix/shared.yaml (defaultSopsFile).
      # validateSopsFiles = false here, so eval passes before the key exists;
      # activation (sops-install-secrets) needs it present.
      vaultwarden_admin_token = { };

      # kleinbem-auth (better-auth login for kleinbem.dev). Per-container file,
      # scoped to core_pi in kleinbem-secrets/.sops.yaml. better_auth_secret is
      # populated; google_/facebook_ are empty until the OAuth apps exist — the
      # service starts fine with no providers (see nix-presets preset).
      kleinbem_auth_better_auth_secret = {
        sopsFile = "${inputs.nix-secrets}/nix/per-container/kleinbem-auth.yaml";
        key = "better_auth_secret";
      };
      kleinbem_auth_google_client_id = {
        sopsFile = "${inputs.nix-secrets}/nix/per-container/kleinbem-auth.yaml";
        key = "google_client_id";
      };
      kleinbem_auth_google_client_secret = {
        sopsFile = "${inputs.nix-secrets}/nix/per-container/kleinbem-auth.yaml";
        key = "google_client_secret";
      };
      kleinbem_auth_facebook_client_id = {
        sopsFile = "${inputs.nix-secrets}/nix/per-container/kleinbem-auth.yaml";
        key = "facebook_client_id";
      };
      kleinbem_auth_facebook_client_secret = {
        sopsFile = "${inputs.nix-secrets}/nix/per-container/kleinbem-auth.yaml";
        key = "facebook_client_secret";
      };

      # Attic Binary Cache
      attic_server_token_rs256 = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/core-pi.yaml";
      };
      # Read-only pull token — activates modules/nixos/attic-pull.nix (netrc
      # Bearer auth + NetBird routing). Without it the host gets 401 from the
      # private cache and the nightly upgrade rebuilds the linux-rpi kernel
      # on-device until RuntimeMaxSec kills it.
      attic_pull_token = { };

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
        sopsFile = "${inputs.nix-secrets}/nix/per-host/core-pi.yaml";
      };
      cloudflare_tunnel_id = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/core-pi.yaml";
      };
      cloudflare_tunnel_secret = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/core-pi.yaml";
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
