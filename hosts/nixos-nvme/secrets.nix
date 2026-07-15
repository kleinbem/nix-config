{
  pkgs,
  inputs,
  config,
  myInventory,
  ...
}:

{
  # ==========================================
  # SOPS — Secrets Management
  # ==========================================
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";
    # Use host SSH keys for automated decryption (avoids YubiKey prompts for background tasks)
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = [ ]; # No GPG keys used
    useSystemdActivation = true;
    age.plugins = [
      pkgs.age-plugin-yubikey
      pkgs.age-plugin-tpm
    ];

    # --- Secret Declarations ---
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
      };
      github_runner_nix_config = {
        owner = "github-runner";
      };
      u2f_keys = { };

      # Service Internal Secrets
      n8n_encryption_key = { };
      n8n_basic_auth_password = { };
      n8n_jwt_secret = { };
      n8n_user_management_main_user_email = { };
      n8n_user_management_main_user_password = { };
      openwebui_secret_key = { };
      langfuse_nextauth_secret = { };
      langfuse_salt = { };

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
      vllm_huggingface_token = { };
      langfuse_public_key = {
        mode = "0444";
      };
      langfuse_secret_key = {
        mode = "0444";
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
      homepage_n8n_key = { };
      homepage_openwebui_key = { };

      # Syncthing
      # syncthing_gui_password = { };

      # Paperless
      paperless_password = {
        neededForUsers = true;
      };
    };

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
      "litellm.env" = {
        mode = "0444";
        content = ''
          # Optional: OpenAI/Anthropic keys for backends
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
    };
  };
}
