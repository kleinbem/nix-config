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
      local_github_actions_runner = {
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
      webui_secret_key = { };
      langfuse_nextauth_secret = { };
      langfuse_salt = { };

      # API Keys
      github_pat = {
        owner = "martin";
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
      attic_server_token_rs256 = { };
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
          WEBUI_SECRET_KEY=${config.sops.placeholder.webui_secret_key}
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
      "attic.env" = {
        mode = "0444";
        content = ''
          ATTIC_SERVER_TOKEN_RS256_SECRET="${config.sops.placeholder.attic_server_token_rs256}"
        '';
      };
      # "syncthing.env".content = ''
      #   SYNCTHING_GUI_PASSWORD=${config.sops.placeholder.syncthing_gui_password}
      # '';
    };
  };
}
