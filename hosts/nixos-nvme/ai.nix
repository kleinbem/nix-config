{
  config,
  lib,
  myInventory,
  ...
}:

{
  # MeshLLM on the iGPU (Vulkan): a MoE coder with 3B active params per token,
  # usable without a discrete GPU. Started by hand (`sudo systemctl start
  # mesh-llm`): idle, its ~25 GB goes to swap and starves builds.
  my.services.meshLlm = {
    enable = true;
    autoStart = false;
    models = [ "Qwen3-Coder-30B-A3B-Instruct-Q4_K_M" ];
  };

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
      hostIP = myInventory.network.nodes.caddy.ip;
      proxyTargets = lib.filterAttrs (_: v: v ? externalPort) myInventory.network.nodes;
      globalMaintenance = myInventory.globalMaintenance or false;
      hostDataDir = "/var/lib/caddy";
      memoryLimit = "512M";
      tls = {
        enable = false; # Handled internally by caddy/default.nix to avoid sidecar conflict
        serverPort = 0;
        upstreams = [ ];
      };
    };

    # Off: monitoring runs on mac-mini with the same inventory IP. Also set in
    # containers.nix, so flipping only one copy is a conflicting-definition error.
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
      autoStart = false; # Manual start for testing
      # Both only exist while enable = true (gated in secrets.nix).
      secretsFile = config.sops.templates."langfuse.env".path;
      dbPasswordFile = config.sops.secrets.langfuse_db_password.path;
    };

    langgraph = {
      enable = false;
      ip = "${myInventory.network.nodes.langgraph.ip}/24";
      hostDataDir = "/var/lib/images/langgraph";
      autoStart = false; # Manual start for testing
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

  # Only dirs no preset owns. Don't add blanket rules for other containers'
  # data dirs: their presets set the right owner, and a rule here conflicts.
  systemd.tmpfiles.rules = [
    "d /var/lib/images/agent-team 0755 1000 100 - -"
    "d /var/lib/images/agent-team/workspace 0775 1000 100 - -"
    "d /var/lib/images/agent-team/state 0700 1000 100 - -"
    "d /var/lib/images/podman/tmp 1777 root root - -"
  ];

}
