{ inputs, config, ... }:
{
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";
    validateSopsFiles = false;

    secrets = {
      # Identity (Authelia)
      authelia_session_secret = { };
      authelia_jwt_secret = { };
      authelia_storage_encryption_key = { };

      # Attic Binary Cache
      attic_server_token_rs256 = { };
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

      # GitHub Runner (optional)
      github_runner_pat = {
        mode = "0440";
        group = "wheel";
      };

      # Cloudflare Tunnel
      cloudflare_account_id = { };
      cloudflare_tunnel_id = { };
      cloudflare_tunnel_secret = { };
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
