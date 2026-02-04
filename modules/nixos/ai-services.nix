{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.ai;
  images = "/images";

  ollamaHome = "${images}/ollama";
  ollamaModels = "${ollamaHome}/models";

in
{
  options.my.services.ai = {
    enable = lib.mkEnableOption "AI Services";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.ollama
      pkgs.silverbullet
      pkgs.code-server
    ];

    # --- dedicated system users/groups ---
    users = {
      groups = {
        ollama = { };
      };
      users = {
        ollama = {
          isSystemUser = true;
          group = "ollama";
          home = ollamaHome;
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

        ];
      };

      # ensure directories exist with sane perms
      tmpfiles.rules = [
        "d ${ollamaHome}       0750 ollama    ollama    - -"
        "d ${ollamaModels}     0750 ollama    ollama    - -"

      ];

      services = {
        ollama = {
          wantedBy = lib.mkForce [ ];
          partOf = [ "ai-services.target" ];
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
  };
}
