{
  user = "martin";

  # ─── Managed Hosts ──────────────────────────────────────────
  hosts = {
    nixos-nvme = {
      ip = "10.85.46.1";
      system = "x86_64-linux";
      deployType = "local"; # Deployed via apply-local
      tags = [
        "workstation"
        "desktop"
      ];
    };
    router-1 = {
      ip = "192.168.1.2"; # TODO: Set actual router IP
      system = "aarch64-linux";
      deployType = "ssh";
      tags = [
        "router"
        "lxc"
      ];
    };
    router-2 = {
      ip = "192.168.1.3"; # TODO: Set actual router IP
      system = "aarch64-linux";
      deployType = "ssh";
      tags = [
        "router"
        "lxc"
      ];
    };
    orin-nano = {
      ip = "192.168.1.10"; # TODO: Set actual Orin IP
      system = "aarch64-linux";
      deployType = "ssh";
      tags = [
        "edge"
        "ai"
        "jetson"
      ];
    };
    rpi5-1 = {
      ip = "192.168.1.20"; # TODO: Set actual RPi IP
      system = "aarch64-linux";
      deployType = "ssh";
      tags = [ "raspberry-pi" ];
    };
    rpi5-2 = {
      ip = "192.168.1.21"; # TODO: Set actual RPi IP
      system = "aarch64-linux";
      deployType = "ssh";
      tags = [ "raspberry-pi" ];
    };
  };

  git = {
    name = "kleinbem";
    email = "martin.kleinberger@gmail.com";
  };
  hardware = {
    gpuRenderNode = "/dev/dri/renderD128";
  };
  network = {
    globalMaintenance = false;
    subnet = "10.85.46.0/24";
    bridge = "cbr0";
    hostIP = "10.85.46.107"; # Caddy Entry Point
    nodes = {
      # Infrastructure
      caddy = {
        ip = "10.85.46.107";
        meta = {
          name = "Caddy Proxy";
          category = "Infrastructure";
          icon = "🔄";
          description = "Reverse Proxy & SSL Termination.";
        };
      };

      # App Containers
      dashboard = {
        ip = "10.85.46.103";
        port = 80;
        externalPort = 443; # Default HTTPS
        maintenance = false;
        meta = {
          name = "Dashboard";
          category = "Infrastructure";
          icon = "🏠";
          description = "Homelab Landing Page.";
        };
      };
      silverbullet = {
        ip = "10.85.46.100";
        port = 3030;
        externalPort = 3000;
        meta = {
          name = "SilverBullet";
          category = "Apps";
          icon = "📝";
          description = "Secure knowledge management.";
        };
      };
      n8n = {
        ip = "10.85.46.99";
        port = 5678;
        externalPort = 5678;
        mtls = true;
        meta = {
          name = "n8n Automation";
          category = "Apps";
          icon = "📡";
          description = "Workflow automation engine.";
        };
      };
      code-server = {
        ip = "10.85.46.101";
        port = 4444;
        externalPort = 4444;
        meta = {
          name = "Code Server";
          category = "Dev";
          icon = "💻";
          description = "VS Code IDE in a hardened core container.";
        };
      };
      open-webui = {
        ip = "10.85.46.102";
        port = 8080;
        externalPort = 8080;
        mtls = true;
        meta = {
          name = "Open WebUI";
          category = "AI";
          icon = "🤖";
          description = "AI Chat interface via Ollama.";
        };
      };
      qdrant = {
        ip = "10.85.46.105";
        port = 6333;
        externalPort = 6333;
        mtls = true;
        meta = {
          name = "Qdrant DB";
          category = "AI";
          icon = "🗄️";
          description = "Vector database for AI context.";
        };
      };
      comfyui = {
        ip = "10.85.46.108";
        port = 8188;
        externalPort = 8188;
        meta = {
          name = "ComfyUI";
          category = "AI Engineering";
          icon = "🎨";
          description = "Advanced Visual Generation.";
        };
      };
      langflow = {
        ip = "10.85.46.109";
        port = 7860;
        externalPort = 7860;
        meta = {
          name = "Langflow";
          category = "AI Engineering";
          icon = "🌊";
          description = "Visual AI Agent Designer.";
        };
      };
      langfuse = {
        ip = "10.85.46.110";
        port = 3000;
        externalPort = 3000;
        meta = {
          name = "Langfuse";
          category = "AI Engineering";
          icon = "👁️";
          description = "LLM telemetry and tracing.";
        };
      };
      vllm = {
        ip = "10.85.46.111";
        port = 8000;
        externalPort = 8000;
        meta = {
          name = "vLLM";
          category = "AI Engineering";
          icon = "⚡";
          description = "High-throughput model serving.";
        };
      };
      openclaw = {
        ip = "10.85.46.112";
        meta = {
          name = "OpenClaw";
          category = "AI Engineering";
          icon = "🐾";
          description = "Dedicated agent framework.";
        };
      };
      agent-zero = {
        ip = "10.85.46.113";
        port = 50001;
        externalPort = 50001;
        mtls = true;
        meta = {
          name = "Agent Zero";
          category = "AI";
          icon = "🕵️";
          description = "Autonomous AI agent framework.";
        };
      };

      # Host-level Services (10.85.46.1)
      cockpit = {
        ip = "10.85.46.1";
        port = 9091;
        externalPort = 9090;
        secure = true;
        meta = {
          name = "Cockpit";
          category = "Infrastructure";
          icon = "🚀";
          description = "System Administration.";
        };
      };
      cups = {
        ip = "10.85.46.1";
        port = 631;
        externalPort = 631;
        secure = true; # Uses https upstream
        meta = {
          name = "CUPS Printing";
          category = "Infrastructure";
          icon = "🖨️";
          description = "Print server management.";
        };
      };
      glances = {
        ip = "10.85.46.1";
        port = 61208;
        externalPort = 61208;
        meta = {
          name = "Glances";
          category = "Infrastructure";
          icon = "📊";
          description = "System metrics and telemetry.";
        };
      };

      # Services not currently proxied by Caddy but present
      ollama = {
        ip = "10.85.46.104";
        port = 11434;
        mtls = true;
        meta = {
          name = "Ollama";
          category = "AI";
          icon = "🦙";
          description = "Local LLM Backend.";
        };
      };
      playground = {
        ip = "10.85.46.106";
        meta = {
          name = "Playground";
          category = "Dev";
          icon = "🎡";
          description = "Dev sandbox (Shell/SSH Access Only).";
        };
      };
    };
  };
}
