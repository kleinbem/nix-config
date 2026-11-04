# nixos-nvme core host secrets. Secrets under lib.optionalAttrs <feature>.enable
# need no provisioned key while that feature is off; the rest always do.
{
  pkgs,
  config,
  lib,
  myInventory,
  secretFile,
  ...
}:

let
  hostSops = secretFile "nix/per-host/nixos-nvme.yaml";
  # Gated on the key so eval works before it exists (sops-nix fails
  # activation on a missing key).
  hasHassCliToken =
    builtins.pathExists hostSops
    && lib.hasInfix "\nhass_cli_token:" ("\n" + builtins.readFile hostSops);
in
{
  # ==========================================
  # SOPS — Secrets Management
  # ==========================================
  sops = {
    # Use host SSH keys for automated decryption (avoids YubiKey prompts for background tasks)
    age.sshKeyPaths = [ "/nix/persist/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = [ ]; # No GPG keys used
    useSystemdActivation = true;
    age.plugins = [
      pkgs.age-plugin-yubikey
      pkgs.age-plugin-tpm
    ];

    # --- Secret Declarations ---
    # Secrets below with an explicit sopsFile live in nix/per-host/nixos-nvme.yaml
    # (only this host + masters can decrypt); everything else falls through to
    # defaultSopsFile (nix/shared.yaml, every NixOS host can decrypt).
    secrets = {
      # Long-lived token of HA's `cli` user, read by the hass-cli wrapper in
      # nix-devshells #workspace (never exported into shell environments).
      hass_cli_token = lib.mkIf hasHassCliToken {
        sopsFile = hostSops;
        owner = "martin";
        mode = "0400";
      };
      netbird_setup_key = { };
      # Read-only Attic pull token; activates modules/nixos/attic-pull.nix so
      # the daemon substitutes from the private cache.
      attic_pull_token = { };
      rclone_config = {
        owner = "martin";
        group = "wheel";
        mode = "0440";
      };
      github_read_all_token = {
        mode = "0440";
        # The nix-daemon needs to be able to read this file
        group = "wheel";
      };
      u2f_keys = { };
      # Buzz (Nostr relay). The S3 keys come from the one-time init at the
      # bottom of nix-presets/containers/buzz.nix.
      buzz_relay_private_key = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
      buzz_user_private_key = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
        owner = "martin";
        group = "users";
        mode = "0400";
      };
      # HA-MCP "Secret URL" (the URL is the credential), read by nix-presets'
      # modules.mcp.homeAssistant wrapper. Create the HA-MCP Server integration
      # in HA, then `sops --set '["ha_mcp_url"] "<url>"' nix/per-host/nixos-nvme.yaml`.
      ha_mcp_url = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
        owner = "martin";
        group = "users";
        mode = "0400";
      };

      # Attic push token for `just deployment::push-cache` (the push after a
      # switch). Decrypted by the host key at activation, so the push needs no
      # YubiKey; the recipe falls back to decrypting it with Martin's key
      # where this file is absent.
      attic_push_token = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
        owner = "martin";
        group = "users";
        mode = "0400";
      };

      buzz_garage_rpc_secret = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      }; # `openssl rand -hex 32`
      buzz_garage_admin_token = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      }; # `openssl rand -base64 32`
      # 0444: services.typesense reads apiKeyFile as the unprivileged
      # `typesense` user. No new exposure: buzz.env (0444) holds it too.
      buzz_typesense_api_key = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
        mode = "0444";
      };
      buzz_s3_access_key = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
      buzz_s3_secret_key = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };

      # Service Internal Secrets
      n8n_encryption_key = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
      n8n_basic_auth_password = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
      n8n_jwt_secret = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
      n8n_user_management_main_user_email = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
      n8n_user_management_main_user_password = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
      openwebui_secret_key = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
      langfuse_nextauth_secret = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
      langfuse_salt = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };

      # API Keys
      github_pat = {
        owner = "martin";
        group = "wheel";
        mode = "0440";
      };
      brave_api_key = {
        owner = "martin";
      };
      github_app_id = {
        owner = "martin";
      };
      github_app_installation_id = {
        owner = "martin";
      };

      github_app_private_key = {
        owner = "martin";
      };
      langfuse_public_key = {
        mode = "0444";
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
      langfuse_secret_key = {
        mode = "0444";
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };

      # Backup Secrets
      restic_password = {
        owner = "martin";
      }; # User backup
      restic_system_password = { }; # Root backup

      # Dashboard Keys
      homepage_n8n_key = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
      homepage_openwebui_key = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };

      # Syncthing
      # syncthing_gui_password = { };

      # Paperless
      paperless_password = {
        neededForUsers = true;
      };
    }
    # Secrets below are gated on their feature: activation fails if a declared
    # key is missing from sops. To enable one, add the key first (e.g.
    # `openssl rand -hex 32` into nix/per-host/nixos-nvme.yaml), then flip the flag.
    # LiteLLM master key: mints virtual keys, teams, budgets.
    // lib.optionalAttrs config.my.containers.litellm.enable {
      litellm_master_key = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
    }
    # Password of langfuse's least-privilege Postgres role.
    // lib.optionalAttrs config.my.containers.langfuse.enable {
      langfuse_db_password = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
    }
    # GitHub runner registration token.
    // lib.optionalAttrs config.my.containers.github-runner.enable {
      github_runner_pat = {
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
    }
    # AnythingLLM API key (created in its UI, Settings → API Keys) for the
    # vault sync, which runs as a home-manager user service.
    // lib.optionalAttrs config.my.anythingllmVaultSync.enable {
      anythingllm_api_key = {
        owner = "martin";
        sopsFile = secretFile "nix/per-host/nixos-nvme.yaml";
      };
    };
    # (Stalwart's admin secret lives with the container, on mac-mini —
    # hosts/mac-mini/secrets.nix, keyed to nix/per-container/stalwart.yaml.)

    # --- Templated Env Files ---
    templates = {
      "homepage.env" = {
        mode = "0444";
        content = ''
          HOMEPAGE_VAR_N8N_KEY=${config.sops.placeholder.homepage_n8n_key}
          HOMEPAGE_VAR_OPENWEBUI_KEY=${config.sops.placeholder.homepage_openwebui_key}
        '';
      };
      "openwebui.env" = {
        mode = "0444";
        content = ''
          WEBUI_SECRET_KEY=${config.sops.placeholder.openwebui_secret_key}
        '';
      };
      "agent-team.env" = {
        mode = "0444";
        content = ''
          LANGFUSE_PUBLIC_KEY=${config.sops.placeholder.langfuse_public_key}
          LANGFUSE_SECRET_KEY=${config.sops.placeholder.langfuse_secret_key}
        '';
      };
      "buzz.env" = {
        mode = "0444";
        content = ''
          BUZZ_RELAY_PRIVATE_KEY=${config.sops.placeholder.buzz_relay_private_key}
          GARAGE_RPC_SECRET=${config.sops.placeholder.buzz_garage_rpc_secret}
          GARAGE_ADMIN_TOKEN=${config.sops.placeholder.buzz_garage_admin_token}
          # Created via the one-time init at the bottom of
          # nix-presets/containers/buzz.nix (garage bucket create buzz-media
          # + garage key create buzz-relay-key), 2026-08-09.
          BUZZ_S3_ACCESS_KEY=${config.sops.placeholder.buzz_s3_access_key}
          BUZZ_S3_SECRET_KEY=${config.sops.placeholder.buzz_s3_secret_key}
          TYPESENSE_API_KEY=${config.sops.placeholder.buzz_typesense_api_key}
        '';
      };
      "n8n.env" = {
        mode = "0444";
        content = ''
          N8N_ENCRYPTION_KEY=${config.sops.placeholder.n8n_encryption_key}
          N8N_BASIC_AUTH_PASSWORD=${config.sops.placeholder.n8n_basic_auth_password}
          N8N_USER_MANAGEMENT_JWT_SECRET=${config.sops.placeholder.n8n_jwt_secret}
          N8N_USER_MANAGEMENT_MAIN_USER_EMAIL=${config.sops.placeholder.n8n_user_management_main_user_email}
          N8N_USER_MANAGEMENT_MAIN_USER_PASSWORD=${config.sops.placeholder.n8n_user_management_main_user_password}
        '';
      };
      # json-exporter config for the GitHub Actions dashboard (monitoring container).
      # Module mappings + the GitHub API bearer token (reuses github_pat — classic
      # repo scope covers Actions-read + self-hosted-runner-read). The token lives
      # here (not in the store) because json-exporter needs it inside its config.
      "json-exporter.yml" = {
        mode = "0444";
        content = ''
          modules:
            runners:
              headers:
                Authorization: "Bearer ${config.sops.placeholder.github_pat}"
                Accept: "application/vnd.github+json"
                X-GitHub-Api-Version: "2022-11-28"
              metrics:
                - name: github_runner
                  type: object
                  help: "Self-hosted runner (value=busy 1/0; label status=online/offline)"
                  path: '{.runners[*]}'
                  labels:
                    name: '{.name}'
                    status: '{.status}'
                  values:
                    busy: '{.busy}'
            runs_count:
              headers:
                Authorization: "Bearer ${config.sops.placeholder.github_pat}"
                Accept: "application/vnd.github+json"
                X-GitHub-Api-Version: "2022-11-28"
              metrics:
                - name: github_workflow_runs
                  type: value
                  help: "Workflow runs in the queried status"
                  path: '{.total_count}'
        '';
      };
      # "syncthing.env".content = ''
      #   SYNCTHING_GUI_PASSWORD=${config.sops.placeholder.syncthing_gui_password}
      # '';
    }
    // lib.optionalAttrs config.my.containers.langfuse.enable {
      # 0400: carries the DB password; root reads it inside the container.
      "langfuse.env" = {
        mode = "0400";
        content = ''
          DATABASE_URL=postgresql://langfuse:${config.sops.placeholder.langfuse_db_password}@10.85.46.124:5432/langfuse
          NEXTAUTH_SECRET=${config.sops.placeholder.langfuse_nextauth_secret}
          SALT=${config.sops.placeholder.langfuse_salt}
          NEXTAUTH_URL=http://${myInventory.network.nodes.langfuse.ip}:3000
        '';
      };
    }
    // lib.optionalAttrs config.my.containers.litellm.enable {
      "litellm.env" = {
        mode = "0444";
        content = ''
          LITELLM_MASTER_KEY=${config.sops.placeholder.litellm_master_key}
          # Per-backend API keys go here as they're added — each backend's
          # apiKeyEnvVar (my.containers.litellm.backends[].apiKeyEnvVar)
          # must name a var defined in this file. Current backends
          # (qwen-32b-ollama, gemma-2b-orin) are unauthenticated local
          # servers, apiKeyEnvVar = null, nothing needed here for them yet.
        '';
      };
    };
  };
}
