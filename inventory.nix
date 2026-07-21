{
  user = "martin";

  # ─── Tang NBDE Servers ──────────────────────────────────────
  # All physical hosts that run the Tang service (my.services.tang.enable = true).
  # waitForTang in each host's initrd polls this list; clevis only needs one
  # server to respond. A host's own Tang is not up during its own initrd unlock.
  tangServers = [
    "http://10.0.0.5:7654" # nixos-nvme (LAN interface)
    "http://10.0.0.15:7654" # orin-nano
    "http://10.0.0.22:7654" # core-pi
    "http://10.0.0.30:7654" # nasbook
    "http://10.0.0.21:7654" # hass-pi (planned, not yet active)
  ];

  # ─── Managed Hosts ──────────────────────────────────────────
  hosts = {
    nixos-nvme = {
      ip = "10.85.46.1"; # Container bridge IP
      physicalIp = "10.0.0.5"; # LAN IP for routing
      netbirdIp = "100.117.212.232"; # Mesh IP (stable per enrollment; re-enrolling mints a new one)
      system = "x86_64-linux";
      deployType = "local"; # Deployed via apply-local
      tags = [
        "workstation"
        "desktop"
      ];
    };
    # (LXC "brain" containers router-1/.3, router-2/.4, net-brain/.7 removed
    # 2026-07-18 — never deployed; every planned tenant lives on the fleet.
    # ap-upstairs keeps the lxc-host capability if a network-layer need
    # ever materializes. .3/.4/.7 are free.)
    core-gateway = {
      ip = "10.0.0.1"; # Physical BPI-R4 (Main Gateway - Downstairs) — infra VLAN gateway
      type = "openwrt";
      tags = [
        "physical"
        "gateway"
        "core"
      ];
    };
    # Router fleet naming: role + location (ap-<location>); the single
    # gateway is core-gateway. Future extenders: ap-garden, ap-barn, …
    # (.6 in the .1–.9 network-layer range stays free for the next unit).
    ap-upstairs = {
      ip = "10.0.0.2"; # Physical BPI-R4 (wired-trunk AP — Upstairs)
      type = "openwrt";
      tags = [
        "physical"
        "ap"
        "lxc-host"
      ];
    };
    orin-nano = {
      ip = "10.0.0.15"; # LAN DHCP IP — assign static or use NetBird for production
      system = "aarch64-linux";
      deployType = "ssh";
      tags = [
        "edge"
        "ai"
        "jetson"
      ];
    };
    core-pi = {
      ip = "10.0.0.22";
      netbirdIp = "100.117.146.201"; # Mesh IP — THE cache entrypoint (caddy/attic); attic-pull.nix + infra/netbird/dns.tf point here
      system = "aarch64-linux";
      deployType = "ssh";
      tags = [
        "raspberry-pi"
        "central"
      ];
    };
    hass-pi = {
      ip = "10.0.0.21"; # Raspberry Pi — not yet active
      netbirdIp = "100.117.163.227"; # Mesh IP (stable per enrollment)
      system = "aarch64-linux";
      deployType = "ssh";
      tags = [
        "raspberry-pi"
        "home-assistant"
      ];
    };
    phone = {
      system = "aarch64-linux";
      deployType = "local";
      tags = [
        "mobile"
        "android"
      ];
    };
    nasbook = {
      ip = "10.0.0.30"; # infra VLAN — NAS + Tang mesh member (fleet is all-10.x)
      system = "x86_64-linux";
      deployType = "ssh";
      tags = [
        "nas"
        "storage"
        "hub"
      ];
    };
  };

  git = {
    name = "kleinbem";
    # Stays on gmail until Phase 1 (Stalwart) provides a real kleinbem.dev
    # mailbox and we verify it on the GitHub account — GitHub's "verified
    # signature" rule checks the committer email against verified emails on
    # the account. Switching this address before then breaks signed pushes
    # to branch-protected repos.
    email = "martin.kleinberger@gmail.com";
  };
  hardware = {
    gpuRenderNode = "/dev/dri/renderD128";
  };
  network = {
    globalMaintenance = false;
    subnet = "10.85.46.0/24";
    bridge = "cbr0";
    hostIP = "10.85.48.107"; # Caddy Entry Point
    nodes = {
      # Infrastructure
      caddy = {
        ip = "10.85.48.107";
        meta = {
          name = "Caddy Proxy";
          category = "Infrastructure";
          icon = "🔄";
          description = "Reverse Proxy & SSL Termination.";
        };
      };
      crowdsec = {
        ip = "10.85.48.119";
        port = 8080;
        meta = {
          name = "CrowdSec LAPI";
          category = "Security";
          icon = "🛡️";
          description = "Intrusion detection & IP reputation engine.";
        };
      };

      # App Containers
      dashboard = {
        ip = "10.85.48.103";
        port = 80;
        externalPort = 443; # Default HTTPS
        domain = "home.kleinbem.dev";
        maintenance = false;
        auth = false; # Gated at the edge by Cloudflare Access (terraform/cloudflare-access.tf); Authelia retired here
        meta = {
          name = "Dashboard";
          category = "Infrastructure";
          icon = "🏠";
          description = "Homelab Landing Page.";
        };
      };
      attic = {
        ip = "10.85.48.120";
        port = 8080;
        externalPort = 443;
        domain = "cache.kleinbem.dev";
        meta = {
          name = "Attic Binary Cache";
          category = "Infrastructure";
          icon = "📦";
          description = "Nix binary cache server.";
        };
      };
      ntfy = {
        ip = "10.85.48.131"; # Core-Pi — deploy signal must not depend on the workstation being on
        port = 2586;
        externalPort = 443;
        domain = "ntfy.kleinbem.dev";
        # No SSO: CI publishes the fleet-deploy signal with a plain curl and
        # devices long-poll anonymously — Authelia would break both. Access
        # control is the unguessable topic name (sops: ntfy_deploy_topic),
        # and the only subscriber action is "start nixos-upgrade.service",
        # which pulls the CI-gated production tag anyway.
        auth = false;
        meta = {
          name = "ntfy Push";
          category = "Infrastructure";
          icon = "📣";
          description = "Pub/sub notifications — fleet deploy signal from CI.";
        };
      };
      garage = {
        ip = "10.85.46.1"; # host-native service on the cbr0 bridge IP (NOT a container)
        port = 3900;
        externalPort = 443;
        domain = "s3.kleinbem.dev";
        # No SSO/mTLS: S3 clients authenticate with their own SigV4 access keys
        # (like the cache — must NOT be Authelia-gated, that breaks SDK clients).
        # NOTE: large objects (backups) should route over NetBird to bypass
        # Cloudflare's 100 MiB upload cap, same as Attic — this tunnel vhost is
        # for general/small-object + admin access.
        auth = false;
        meta = {
          name = "Garage S3";
          category = "Infrastructure";
          icon = "🗄️";
          description = "Self-hosted S3 object storage (backups, cache, tofu-state).";
        };
      };
      n8n = {
        ip = "10.85.46.99";
        port = 5678;
        externalPort = 443;
        domain = "n8n.kleinbem.dev";
        mtls = true;
        auth = true; # Protected by Authelia
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
        externalPort = 443;
        domain = "code.kleinbem.dev";
        meta = {
          name = "Code Server";
          category = "Dev";
          icon = "💻";
          description = "VS Code IDE in a hardened core container.";
        };
      };
      open-webui = {
        ip = "10.85.48.102"; # Core-Pi
        port = 8080;
        externalPort = 443;
        domain = "chat.kleinbem.dev";
        mtls = true;
        meta = {
          name = "Open WebUI";
          category = "AI";
          icon = "🤖";
          description = "AI Chat interface via Ollama.";
        };
      };
      qdrant = {
        ip = "10.85.47.105"; # NASbook
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
          description = "Advanced Visual Generation. [AIRLOCK: Restricted Egress]";
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
          description = "Visual AI Agent Designer. [AIRLOCK: Restricted Egress]";
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
          description = "LLM telemetry and tracing. [AIRLOCK: Restricted Egress]";
        };
      };
      ollama-rpi = {
        ip = "10.85.46.117";
        port = 11434;
        meta = {
          name = "Ollama RPi 5";
          category = "AI";
          icon = "🦙";
          description = "CPU-only Ollama inference (ARM64).";
        };
      };
      ollama-orin = {
        ip = "10.85.46.104";
        port = 11434;
        meta = {
          name = "Ollama Orin Nano";
          category = "AI";
          icon = "🦙";
          description = "NVIDIA CUDA-accelerated Ollama inference.";
        };
      };
      openclaw = {
        ip = "10.85.48.112"; # Core-Pi
        meta = {
          name = "OpenClaw";
          category = "AI Engineering";
          icon = "🐾";
          description = "Dedicated agent framework.";
        };
      };
      agent-zero = {
        ip = "10.85.48.113"; # Core-Pi
        port = 50001;
        externalPort = 50001;
        mtls = true;
        meta = {
          name = "Agent Zero";
          category = "AI";
          icon = "🕵️";
          description = "Autonomous AI agent framework. [AIRLOCK: Restricted Egress]";
        };
      };
      agent-team = {
        ip = "10.85.47.118"; # NASbook
        port = 8000;
        externalPort = 8008;
        mtls = true;
        meta = {
          name = "AI Agent Team";
          category = "AI";
          icon = "👥";
          description = "Enterprise Role-Based Agent Team (CrewAI). [AIRLOCK: Restricted Egress]";
        };
      };
      monitoring = {
        enabled = true;
        ip = "10.85.48.114"; # Core-Pi
        port = 3000;
        externalPort = 3001;
        auth = true; # Protected by Authelia
        meta = {
          name = "Monitoring";
          category = "Infrastructure";
          icon = "📊";
          description = "VictoriaMetrics + Grafana Stack.";
        };
      };
      alertmanager = {
        enabled = true;
        ip = "10.85.47.114"; # Runs in monitoring container
        port = 9093;
        externalPort = 9093;
        auth = true; # Protected by Authelia
        meta = {
          name = "Alertmanager";
          category = "Infrastructure";
          icon = "🔔";
          description = "Alert Routing & Management.";
        };
      };
      litellm = {
        ip = "10.85.46.115";
        port = 4000;
        externalPort = 4000;
        mtls = true;
        meta = {
          name = "LiteLLM Gateway";
          category = "AI";
          icon = "🔌";
          description = "Unified AI API Gateway & Proxy. [AIRLOCK: Restricted Egress]";
        };
      };
      loki = {
        ip = "10.85.47.116"; # NASbook
        port = 3100;
        meta = {
          name = "Loki Logging";
          category = "Infrastructure";
          icon = "📜";
          description = "Centralized Log Aggregator.";
        };
      };
      netdata = {
        ip = "10.85.46.122";
        port = 19999;
        meta = {
          name = "Netdata";
          category = "Infrastructure";
          icon = "📊";
          description = "Real-time per-second telemetry.";
        };
      };
      authelia = {
        ip = "10.85.48.123";
        port = 9091;
        externalPort = 9091;
        meta = {
          name = "Authelia SSO";
          category = "Identity";
          icon = "🔐";
          description = "Single Sign-On & 2FA.";
        };
      };
      home-assistant = {
        ip = "10.85.49.10"; # Hass-Pi
        port = 8123;
        meta = {
          name = "Home Assistant";
          category = "Apps";
          icon = "🏠";
          description = "Smart Home Automation.";
        };
      };

      cups = {
        ip = "10.85.46.124";
        port = 631;
        secure = true; # Uses https upstream
        meta = {
          name = "CUPS Printing";
          category = "Infrastructure";
          icon = "🖨️";
          description = "Print server management (Containerized).";
        };
      };
      ollama = {
        ip = "10.85.46.125";
        port = 11434;
        meta = {
          name = "Ollama";
          category = "AI";
          icon = "🦙";
          description = "Native Ollama Inference Engine.";
        };
      };
      github-runner = {
        ip = "10.85.46.126";
        meta = {
          name = "GitHub Runner";
          category = "Dev";
          icon = "🏃";
          description = "Isolated CI/CD Runner.";
        };
      };
      syncthing = {
        ip = "10.85.46.127";
        port = 8384;
        externalPort = 8384;
        auth = true; # Protected by Authelia SSO
        meta = {
          name = "Syncthing (Zotac)";
          category = "Infrastructure";
          icon = "🔄";
          description = "File synchronization for the Main Workstation.";
        };
      };
      syncthing-orin = {
        ip = "10.85.46.129";
        port = 8384;
        meta = {
          name = "Syncthing (Orin)";
          category = "Infrastructure";
          icon = "🔄";
          description = "File synchronization for the AI Node.";
        };
      };
      backup = {
        ip = "10.85.47.128"; # Moved to NASbook subnet
        meta = {
          name = "Restic Backup";
          category = "Infrastructure";
          icon = "💾";
          description = "Daily system backup container.";
        };
      };

      # Services not currently proxied by Caddy but present
      frigate = {
        ip = "10.85.46.130";
        port = 5000;
        externalPort = 5000;
        meta = {
          name = "Frigate NVR";
          category = "Security";
          icon = "📹";
          description = "NVR with AI object detection (NVIDIA TensorRT).";
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
      paperless = {
        ip = "10.85.47.131"; # Moved to NASbook subnet
        port = 28981;
        externalPort = 28981;
        auth = true;
        meta = {
          name = "Paperless-ngx";
          category = "Documents";
          icon = "📄";
          description = "Document management system with OCR.";
        };
      };
      anythingllm = {
        ip = "10.85.48.132"; # Moved to Core-Pi subnet
        port = 3001;
        meta = {
          name = "AnythingLLM";
          category = "AI";
          icon = "🧠";
          description = "All-in-one AI workspace and document orchestrator.";
        };
      };
      ente = {
        ip = "10.85.48.133";
        port = 8080;
        externalPort = 443;
        domain = "auth.kleinbem.dev";
        auth = false;
        meta = {
          name = "Ente Auth";
          category = "Identity";
          icon = "🔐";
          description = "E2E Encrypted 2FA & Authenticator Server.";
        };
      };
    };
  };
}
