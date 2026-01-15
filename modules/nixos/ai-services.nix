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
        createHome = false; # We only need the user for ownership
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

        "n8n.service"
      ];
    };

    # ensure directories exist with sane perms
    tmpfiles.rules = [
      "d ${ollamaHome}       0750 ollama    ollama    - -"
      "d ${ollamaModels}     0750 ollama    ollama    - -"
      "d /var/lib/open-webui 0750 openwebui openwebui - -"

      "d ${n8nHome}          0750 n8n       n8n       - -"
      "d ${n8nBinary}        0750 n8n       n8n       - -"
    ];

    services = {
      ollama = {
        wantedBy = lib.mkForce [ ];
        partOf = [ "ai-services.target" ];
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

    # --- N8N ---

  };
}
