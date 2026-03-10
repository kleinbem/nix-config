{
  pkgs,
  inputs,
  config,
  ...
}:

{
  # ==========================================
  # SOPS — Secrets Management
  # ==========================================
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";
    age.keyFile = "/nix/persist/var/lib/sops/age/host.txt";
    useSystemdActivation = true;
    age.plugins = [
      pkgs.age-plugin-yubikey
      pkgs.age-plugin-tpm
    ];

    # --- Secret Declarations ---
    secrets = {
      rclone_config = {
        owner = "martin";
      };
      github_read_all_token = {
        mode = "0440";
        # The nix-daemon needs to be able to read this file
        group = "wheel";
      };
      u2f_keys = { };

      # Service Internal Secrets
      n8n_encryption_key = { };
      n8n_basic_auth_password = { };
      webui_secret_key = { };
      langfuse_nextauth_secret = { };
      langfuse_salt = { };

      # API Keys (Placeholders currently)
      github_pat = { };
      brave_api_key = { };
      vllm_huggingface_token = { };

      # Dashboard Keys
      homepage_n8n_key = { };
      homepage_openwebui_key = { };
    };

    # --- Templated Env Files ---
    templates = {
      "homepage.env".content = ''
        HOMEPAGE_VAR_N8N_KEY=${config.sops.placeholder.homepage_n8n_key}
        HOMEPAGE_VAR_OPENWEBUI_KEY=${config.sops.placeholder.homepage_openwebui_key}
      '';
      "openwebui.env".content = ''
        WEBUI_SECRET_KEY=${config.sops.placeholder.webui_secret_key}
      '';
      "langfuse.env".content = ''
        NEXTAUTH_SECRET=${config.sops.placeholder.langfuse_nextauth_secret}
        SALT=${config.sops.placeholder.langfuse_salt}
      '';
      "vllm.env".content = ''
        HUGGING_FACE_HUB_TOKEN=${config.sops.placeholder.vllm_huggingface_token}
      '';
      "n8n.env".content = ''
        N8N_ENCRYPTION_KEY=${config.sops.placeholder.n8n_encryption_key}
        N8N_BASIC_AUTH_PASSWORD=${config.sops.placeholder.n8n_basic_auth_password}
      '';
    };
  };
}
