{
  config,
  lib,
  pkgs,
  ...
}:

let
  images = "/images";

  ollamaHome = "${images}/ollama";
  ollamaModels = "${ollamaHome}/models";

  openWebuiState = "${images}/open-webui";

  n8nHome = "${images}/n8n";
  n8nBinary = "${n8nHome}/binaryData";
in
{
  environment.systemPackages = [ pkgs.ollama ];

  # --- dedicated system users/groups ---
  users = {
    groups = {
      ollama = { };
      openwebui = { };
      n8n = { };
    };
    users = {
      ollama = {
        isSystemUser = true;
        group = "ollama";
        home = ollamaHome;
        createHome = true;
      };
      openwebui = {
        isSystemUser = true;
        group = "openwebui";
        home = openWebuiState;
        createHome = true;
      };
      n8n = {
        isSystemUser = true;
        group = "n8n";
        home = n8nHome;
        createHome = true;
      };
    };
  };

  # --- Systemd Configuration ---
  systemd = {
    # Systemd Target for manual control
    targets.ai-services = {
      description = "AI Services (Ollama, WebUI, n8n)";
      wants = [
        "ollama.service"
        "open-webui.service"
        "n8n.service"
      ];
    };

    # ensure directories exist with sane perms
    tmpfiles.rules = [
      "d ${ollamaHome}       0750 ollama    ollama    - -"
      "d ${ollamaModels}     0750 ollama    ollama    - -"
      "d ${openWebuiState}   0750 openwebui openwebui - -"
      "d ${n8nHome}          0750 n8n       n8n       - -"
      "d ${n8nBinary}        0750 n8n       n8n       - -"
    ];

    services = {
      ollama = {
        wantedBy = lib.mkForce [ ];
        partOf = [ "ai-services.target" ];
      };

      open-webui = {
        wantedBy = lib.mkForce [ ];
        partOf = [ "ai-services.target" ];
        serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "openwebui";
          Group = "openwebui";
          LoadCredential = [ "webui_secret:${config.sops.secrets."open-webui.env".path}" ];
        };
      };

      n8n = {
        wantedBy = lib.mkForce [ ];
        partOf = [ "ai-services.target" ];
        serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "n8n";
          Group = "n8n";
          # LoadCredential puts the secret in /run/credentials/n8n.service/n8n.env
          LoadCredential = [ "n8n_password:${config.sops.secrets."n8n.env".path}" ];
        };
        environment = {
          N8N_USER_FOLDER = lib.mkForce n8nHome;
        };
      };
    };
  };

  # --- Services Configuration ---
  services = {
    # --- OLLAMA ---
    ollama = {
      enable = true;
      host = "127.0.0.1";
      port = 11434;
      user = "ollama";
      group = "ollama";
      home = ollamaHome;
      models = ollamaModels;
    };

    # --- OPEN-WEBUI ---
    # open-webui = {
    #   enable = true;
    #   host = "127.0.0.1";
    #   port = 3000;
    #   stateDir = openWebuiState;
    #   environment = {
    #     OLLAMA_BASE_URL = "http://127.0.0.1:11434";
    #     # Read secret from Systemd Credential Store
    #     WEBUI_SECRET_KEY_FILE = "%d/webui_secret";
    #   };
    # };

    # --- N8N ---
    n8n = {
      enable = true;
      package = pkgs.stable.n8n;
      openFirewall = false;
      environment = {
        N8N_LISTEN_ADDRESS = "127.0.0.1";
        N8N_PORT = "5678";
        N8N_PROTOCOL = "http";
        N8N_HOST = "localhost";

        N8N_DEFAULT_BINARY_DATA_MODE = "filesystem";
        N8N_BINARY_DATA_STORAGE_PATH = n8nBinary;
        N8N_BASIC_AUTH_ACTIVE = "true";
        N8N_BASIC_AUTH_USER = "admin";
        # Read secret from Systemd Credential Store
        N8N_BASIC_AUTH_PASSWORD_FILE = "%d/n8n_password";
      };
    };
  };
}
