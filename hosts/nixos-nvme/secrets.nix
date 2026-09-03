# nixos-nvme Secrets Management
#
# This file handles core host secrets (database passwords, API keys, etc.).
# Additional secrets are defined in:
#   - ai.nix (LLM/AI API keys, litellm config — gated behind my.ai.enable)
#   - specialisations.nix (secrets only needed for alternative boot profiles)
#
# Rationale for splitting: Secrets are scoped to features that use them.
# This avoids decrypting unnecessary secrets at activation and keeps each
# feature's configuration self-contained. Persona contact info was moved to
# kleinbem-secrets/personas/contact.nix (plain Nix, re-encrypted at deployment).
#
# See also: modules/nixos/keys.nix (public SSH keys)
{
  pkgs,
  inputs,
  config,
  lib,
  myInventory,
  ...
}:

{
  # ==========================================
  # SOPS — Secrets Management
  # ==========================================
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/nix/shared.yaml";
    defaultSopsFormat = "yaml";
    # Use host SSH keys for automated decryption (avoids YubiKey prompts for background tasks)
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = [ ]; # No GPG keys used
    useSystemdActivation = true;

    # Don't fail the *build* validating secret presence against the sops file —
    # matches core-pi/hass-pi. CI builds this host's toplevel with an empty dummy
    # nix/shared.yaml (--override-input nix-secrets /tmp/dummy-secrets, see
    # .github/scripts/setup-dummy-secrets.sh), so sops-install-secrets' build-time
    # manifest check would abort on e.g. "key 'martin_password_hash' cannot be
    # found" — the documented sops-nix CI workaround. Real decryption at
    # activation is unaffected (it uses the real shared/per-host files on the host).
    validateSopsFiles = false;
    age.plugins = [
      pkgs.age-plugin-yubikey
      pkgs.age-plugin-tpm
    ];

    # --- Secret Declarations ---
    # Secrets below with an explicit sopsFile live in nix/per-host/nixos-nvme.yaml
    # (only this host + masters can decrypt); everything else falls through to
    # defaultSopsFile (nix/shared.yaml, every NixOS host can decrypt).
    secrets = {
      netbird_setup_key = { };
      # Read-only Attic pull token — activates modules/nixos/attic-pull.nix so
      # the daemon can substitute from the private cache instead of 401-ing and
      # rebuilding everything CI already pushed. The cache entrypoint (caddy)
      # and attic both live on core-pi since 2026-07-06; nixos-nvme pulls like
      # every other mesh peer via the attic-pull default cacheHostIp.
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
      github_runner_pat = {
        mode = "0440";
        group = "wheel";
      };
      github_runner_nix = {
        owner = "github-runner";
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      github_runner_nix_config = {
        owner = "github-runner";
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      u2f_keys = { };
      # Buzz (Nostr relay) — 32-byte hex Nostr signing key + Garage RPC/admin
      # creds + Typesense admin key + Garage S3 API key (buzz_s3_access_key/
      # buzz_s3_secret_key, created via the one-time init documented at the
      # bottom of nix-presets/containers/buzz.nix, 2026-08-09). buzz_typesense_api_key
      # is also used directly as services.typesense.apiKeyFile (raw value, no
      # template needed there — see hosts/nixos-nvme/containers.nix).
      buzz_relay_private_key = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      buzz_garage_rpc_secret = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      }; # `openssl rand -hex 32`
      buzz_garage_admin_token = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      }; # `openssl rand -base64 32`
      # mode 0444: services.typesense's own module `cat`s apiKeyFile
      # INSIDE its script=, which runs as the unprivileged static
      # `typesense` user (after DynamicUser was disabled for the
      # StateDirectory-vs-bind-mount fix below) — the sops-nix default
      # 0400/root:root left it unreadable there ("Permission denied",
      # confirmed live 2026-08-09). No new exposure: the same value is
      # already sitting in the 0444 buzz.env template two secrets below,
      # readable by every process in this container regardless.
      buzz_typesense_api_key = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
        mode = "0444";
      };
      buzz_s3_access_key = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      buzz_s3_secret_key = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };

      # Service Internal Secrets
      n8n_encryption_key = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      n8n_basic_auth_password = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      n8n_jwt_secret = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      n8n_user_management_main_user_email = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      n8n_user_management_main_user_password = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      openwebui_secret_key = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      langfuse_nextauth_secret = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      langfuse_salt = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };

      # API Keys
      github_pat = {
        owner = "martin";
        group = "github-runner";
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
      vllm_huggingface_token = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      langfuse_public_key = {
        mode = "0444";
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      langfuse_secret_key = {
        mode = "0444";
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };

      # Backup Secrets
      restic_password = {
        owner = "martin";
      }; # User backup
      restic_system_password = { }; # Root backup

      # Identity (Authelia)
      authelia_session_secret = { };
      authelia_jwt_secret = { };
      authelia_storage_encryption_key = { };

      # Dashboard Keys
      homepage_n8n_key = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };
      homepage_openwebui_key = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
      };

      # Syncthing
      # syncthing_gui_password = { };

      # Paperless
      paperless_password = {
        neededForUsers = true;
      };
    }
    # LiteLLM's real admin/management credential — mints virtual keys,
    # Teams, budgets. Gated behind the container's own enable flag: a
    # disabled container must have ZERO activation-time footprint, not
    # require a real secret value nobody's provisioned yet just because
    # the declaration exists. Was a hardcoded "sk-1234" placeholder baked
    # straight into the Nix store (nix-presets/containers/litellm.nix)
    # until 2026-08-09 — real switch-time activation genuinely requires
    # the key to exist in kleinbem-secrets regardless of
    # validateSopsFiles (that only suppresses CI's dummy-file eval-time
    # check, per this file's header comment) — confirmed live: an
    # unconditional declaration broke a real `nixos-rebuild switch` on
    # this host with the key still unprovisioned. Once you actually want
    # to turn litellm on: generate a value (e.g. `openssl rand -hex 32`),
    # `sops nix/per-host/nixos-nvme.yaml`, THEN flip the enable flag.
    // lib.optionalAttrs config.my.containers.litellm.enable {
      litellm_master_key = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/nixos-nvme.yaml";
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
      "langfuse.env" = {
        mode = "0444";
        content = ''
          DATABASE_URL=postgresql://postgres:postgres@10.85.46.124:5432/langfuse
          NEXTAUTH_SECRET=${config.sops.placeholder.langfuse_nextauth_secret}
          SALT=${config.sops.placeholder.langfuse_salt}
          NEXTAUTH_URL=http://${myInventory.network.nodes.langfuse.ip}:3000
        '';
      };
      "agent-team.env" = {
        mode = "0444";
        content = ''
          LANGFUSE_PUBLIC_KEY=${config.sops.placeholder.langfuse_public_key}
          LANGFUSE_SECRET_KEY=${config.sops.placeholder.langfuse_secret_key}
        '';
      };
      "vllm.env" = {
        mode = "0444";
        content = ''
          HUGGING_FACE_HUB_TOKEN=${config.sops.placeholder.vllm_huggingface_token}
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
