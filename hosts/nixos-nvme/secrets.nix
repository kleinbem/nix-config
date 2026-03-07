{
  pkgs,
  inputs,
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
    secrets.rclone_config = {
      owner = "martin";
    };
    secrets.github_read_all_token = {
      mode = "0440";
      # The nix-daemon needs to be able to read this file
      group = "wheel";
    };
    secrets.u2f_keys = { };
    # secrets.homepage_n8n_key = { };
    # secrets.homepage_openwebui_key = { };
    # secrets.langfuse_public_key = { };
    # secrets.langfuse_secret_key = { };
    # secrets.langfuse_host = { };
    # secrets.langfuse_nextauth_secret = { };
    # secrets.langfuse_salt = { };
    # secrets.vllm_huggingface_token = { };
    # secrets.n8n_encryption_key = { };
    # secrets.n8n_basic_auth_password = { };
    # secrets.webui_secret_key = { };

    # --- Templated Env Files ---
    templates = {
      "homepage.env".content = "";
      "openwebui.env".content = "";
      "langfuse.env".content = "";
      "vllm.env".content = "";
      "n8n.env".content = "";
    };
  };
}
