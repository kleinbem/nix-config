{ config, myInventory, ... }:

{
  my.containers = {
    litellm = {
      enable = false;
      ip = "${myInventory.network.nodes.litellm.ip}/24";
      hostDataDir = "/var/lib/images/litellm";
      autoStart = true;
      tls = {
        enable = true;
        serverPort = 4000;
      };
      secretsFile = config.sops.templates."litellm.env".path;
      backends = [
        {
          name = "qwen-32b-ollama";
          url = "http://host.containers.internal:11434";
          model = "ollama/qwen2.5-coder:32b";
        }
        {
          name = "gemma-2b-orin";
          url = "http://${myInventory.network.nodes.ollama-orin.ip}:8000/v1";
          model = "google/gemma-2b";
        }
        {
          name = "qwen-7b-rpi";
          url = "http://${myInventory.network.nodes.ollama-rpi.ip}:8000/v1";
          model = "Qwen/Qwen2.5-Coder-7B-Instruct";
        }
      ];
    };

    playground = {
      enable = false;
      ip = "${myInventory.network.nodes.playground.ip}/24";
      hostDataDir = "/var/lib/images/playground";
      # user = config.my.username; # Restored if needed, but 'martin' is hardcoded in some places anyway
      memoryLimit = "8G";
    };

    caddy = {
      enable = false;
      ip = "${myInventory.network.nodes.caddy.ip}/24";
      hostDataDir = "/var/lib/caddy";
      memoryLimit = "512M";
      tls = {
        enable = false; # Handled internally by caddy/default.nix to avoid sidecar conflict
        serverPort = 0;
        upstreams = [ ];
      };
    };

    monitoring = {
      enable = false;
      ip = "${myInventory.network.nodes.monitoring.ip}/24";
      hostDataDir = "/var/lib/images/monitoring";
      nodeTargets = [
        myInventory.hosts.nixos-nvme.ip
        myInventory.hosts.orin-nano.ip
        myInventory.hosts.core-pi.ip
        myInventory.hosts.hass-pi.ip
        myInventory.hosts.core-gateway.ip
        myInventory.hosts.ap-upstairs.ip
      ];
      ollamaTargets = [
        myInventory.network.nodes.ollama-orin.ip
        myInventory.network.nodes.ollama-rpi.ip
      ];
    };

    agent-zero = {
      enable = false;
      ip = "${myInventory.network.nodes.agent-zero.ip}/24";
      hostDataDir = "/var/lib/images/agent-zero";
      ollamaUrl = "http://localhost:11434"; # Via mTLS sidecar → Ollama on Orin Nano
      tls = {
        enable = true;
        serverPort = 50001;
        upstreams = [
          {
            name = "ollama-orin";
            target = myInventory.network.nodes.ollama-orin.ip;
            port = 11434;
          }
        ];
      };
    };

    comfyui = {
      enable = false;
      ip = "${myInventory.network.nodes.comfyui.ip}/24";
      hostDataDir = "/var/lib/images/comfyui";
      autoStart = false; # Manual start to prevent thermal overload during pull
    };

    langflow = {
      enable = false;
      ip = "${myInventory.network.nodes.langflow.ip}/24";
      hostDataDir = "/var/lib/images/langflow";
      autoStart = false; # Manual start to prevent thermal overload during pull
    };

    langfuse = {
      enable = false;
      ip = "${myInventory.network.nodes.langfuse.ip}/24";
      hostDataDir = "/var/lib/images/langfuse";
      autoStart = true;
      secretsFile = config.sops.templates."langfuse.env".path;
    };

    agent-team = {
      enable = false;
      autoStart = true;
      ip = "${myInventory.network.nodes.agent-team.ip}/24";
      hostDataDir = "/var/lib/images/agent-team";
      manager.humanInTheLoop = true; # Enabled per user request
      secretsFile = config.sops.templates."agent-team.env".path;

      # Team Definition based on industry best practices
      agents = {
        architect = {
          role = "Lead Solutions Architect";
          goal = "Design modular and scalable NixOS configurations.";
          backstory = "Expert in declarative systems and multi-agent orchestration.";
        };
        developer = {
          role = "Nix/Python Developer";
          goal = "Implement clean code based on the Architect's design.";
          backstory = "Specialized in automation and idempotent system configurations.";
        };
        auditor = {
          role = "Security Compliance Auditor";
          goal = "Ensure all changes follow the 'Sanctuary' security policy.";
          backstory = "Zero-trust advocate focused on Least Privilege and Airlocking.";
        };
      };

      tls = {
        enable = true;
        serverPort = 8000;
        upstreams = [
          {
            name = "litellm";
            target = myInventory.network.nodes.litellm.ip;
            port = 4000;
          }
          {
            name = "langfuse";
            target = myInventory.network.nodes.langfuse.ip;
            port = 3000;
          }
        ];
      };
    };
  };

  # Ensure the data directories exist with correct permissions
  systemd.tmpfiles.rules = [
    # "d /var/lib/images/vllm 0777 root root - -" # Removed workstation vLLM directory
    "d /var/lib/images/litellm 0777 root root - -"
    "d /var/lib/images/playground 0777 martin users - -"
    "d /var/lib/caddy 0777 root root - -"
    "d /var/lib/images/monitoring 0777 root root - -"
    "d /var/lib/images/monitoring/grafana 0777 root root - -"
    "d /var/lib/images/comfyui 0777 root root - -"
    "d /var/lib/images/langflow 0777 root root - -"
    "d /var/lib/images/langfuse 0777 root root - -"
    "d /var/lib/images/langfuse/db 0777 root root - -"
    "d /var/lib/images/agent-team 0755 1000 100 - -"
    "d /var/lib/images/agent-team/workspace 0775 1000 100 - -"
    "d /var/lib/images/agent-team/state 0700 1000 100 - -"
    "d /var/lib/images/ollama 0777 ollama ollama - -"
    "Z /var/lib/images/ollama 0777 ollama ollama - -"
    "d /var/lib/images/podman/tmp 1777 root root - -"
  ];

}
