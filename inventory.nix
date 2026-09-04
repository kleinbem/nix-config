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
    "http://10.0.0.16:7654" # mac-mini
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
      ip = "10.0.0.21"; # Raspberry Pi — not yet deployed
      netbirdIp = "100.117.163.227"; # Mesh IP (stable per enrollment)
      system = "aarch64-linux";
      deployType = "ssh";
      tags = [
        "raspberry-pi"
        "home-assistant"
      ];
      # Status: Configuration ready (hosts/hass-pi/default.nix), hardware prepared
      # but not deployed. Deploy when home automation becomes priority.
      # Currently hosts: home-assistant, openclaw (pnpm-deps hash issue keeps
      # it here; see hosts/hass-pi/default.nix line 17-23). Other AI services
      # moved to mac-mini 2026-08-05 (RAM and power constraints).
      #
      # To deploy:
      # 1. Power on Raspberry Pi 5
      # 2. Boot NixOS installer, follow bootstrap steps in docs/DEVICE-TIERS.md
      # 3. Run: sudo nixos-install --flake .#hass-pi
      # 4. Update this comment to remove "not yet deployed"
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
    mac-mini = {
      ip = "10.0.0.16"; # LAN IP — static (cutover from DHCP .70 confirmed 2026-08-03)
      netbirdIp = "100.117.247.175"; # Mesh IP (stable per enrollment)
      system = "x86_64-linux"; # Mid-2011 Mac Mini (Macmini5,x) — Intel, real 64-bit EFI
      deployType = "ssh";
      tags = [
        "desktop"
        "legacy-hardware"
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
        auth = true; # Mesh-only now — Cloudflare Access was its only gate; Authelia replaces it
        meta = {
          name = "Code Server";
          category = "Dev";
          icon = "💻";
          description = "VS Code IDE in a hardened core container.";
        };
      };
      open-webui = {
        ip = "10.85.50.3"; # mac-mini (moved from hass-pi 2026-08-05)
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
        ip = "10.85.49.112"; # Hass-Pi (kept here — pnpm-deps hash mismatch against its pinned upstream flake blocks a fresh build elsewhere, see hosts/hass-pi/default.nix)
        meta = {
          name = "OpenClaw";
          category = "AI Engineering";
          icon = "🐾";
          description = "Dedicated agent framework.";
        };
      };
      agent-zero = {
        ip = "10.85.50.5"; # mac-mini (moved from hass-pi 2026-08-05)
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
      hermes = {
        ip = "10.85.50.7"; # mac-mini (moved from hass-pi 2026-08-05)
        meta = {
          name = "Hermes Agent";
          category = "AI Engineering";
          icon = "🪽";
          description = "Nous Research self-improving agent (Discord gateway, local LLM backend). [AIRLOCK: Restricted Egress]";
        };
      };
      buzz = {
        ip = "10.85.46.131"; # nixos-nvme — Pis (hass-pi/core-pi) too tight on RAM for now
        port = 3000;
        meta = {
          name = "Buzz";
          category = "AI Engineering";
          icon = "🐝";
          description = "Block/Nostr team chat + git + AI-agent workspace, self-hosted from source (no Docker). [AIRLOCK: Restricted Egress]";
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
        ip = "10.85.50.2"; # mac-mini (moved from core-pi 2026-08-04)
        # Not proxied through Caddy under a *.kleinbem.dev domain (unlike
        # n8n/code-server/etc, which pair `port` with a real `externalPort`
        # + `domain`) — reached directly on this port. A stale
        # `externalPort = 3001` used to live here with nothing ever bound to
        # it (Grafana's actual listener is this `port`, set via
        # server.http_port in nix-presets/containers/monitoring.nix); the
        # generic `service-launchers` desktop entry prefers externalPort over
        # port when both exist, so it was silently pointing at a dead port.
        port = 3000;
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
        # Runs inside the SAME monitoring container (containers/monitoring.nix
        # enables prometheus.alertmanager in the same innerConfig as
        # victoriametrics/grafana) — was pointing at 10.85.47.114 (nasbook's
        # subnet), a stale/wrong value predating this move, not something
        # that ever matched the container's real address. Fixed to match
        # monitoring's own IP above.
        ip = "10.85.50.2"; # mac-mini (moved from core-pi 2026-08-04)
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
        externalPort = 443;
        domain = "authelia.kleinbem.dev"; # mesh-only (nix/infra/netbird) — never the tunnel; it's the SSO gate itself
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
        externalPort = 443;
        domain = "frigate.kleinbem.dev";
        auth = true; # Authelia in front; mesh-only (NVR — never on the public tunnel)
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
        ip = "10.85.50.6"; # mac-mini (moved from hass-pi 2026-08-05)
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
      # Self-hosted Bitwarden-compatible password vault for people + personas.
      # core-pi slice (10.85.48.0/24); .135 free. NOT Authelia/Access-gated —
      # forward-auth breaks Bitwarden apps, the CLI and browser extensions;
      # Vaultwarden's own master-password + 2FA is the gate, /admin by token.
      vaultwarden = {
        ip = "10.85.48.135";
        port = 8222;
        externalPort = 443;
        domain = "vault.kleinbem.dev";
        auth = false;
        meta = {
          name = "Vaultwarden";
          category = "Identity";
          icon = "🔐";
          description = "Self-hosted password manager (people + personas).";
        };
      };
      # better-auth social login for kleinbem.dev visitors (container staged
      # disabled on core-pi until kleinbem-secrets + OAuth apps exist).
      # auth = false: this IS the public sign-in surface — never Authelia-gated.
      kleinbem-auth = {
        ip = "10.85.48.140";
        port = 3000;
        externalPort = 443;
        domain = "login.kleinbem.dev";
        auth = false;
        meta = {
          name = "Login";
          category = "Identity";
          icon = "🔑";
          description = "Social login (Google/Facebook) for kleinbem.dev.";
        };
      };
      # Persona-fleet mail (Phase 1). One mailbox per persona at
      # <name>@kleinbem.dev, created imperatively by persona-scaffold.sh.
      # Runs on mac-mini (24/7 host) — .50 subnet. Not Caddy-proxied —
      # SMTP/IMAP can't be Cloudflare-proxied; personas reach it directly
      # on this IP over the mesh. http/8080 (JMAP + webadmin) is the only
      # HTTP surface. See docs/PHASE1_STALWART.md + docs/PHASE1_STALWART_STATUS.md.
      stalwart = {
        ip = "10.85.50.8";
        port = 8080;
        # externalPort → the Caddy preset auto-generates a reverse-proxy
        # vhost (mail.kleinbem.dev + stalwart.local → 10.85.50.8:8080,
        # `tls internal`). This is the webadmin/JMAP HTTP surface only —
        # SMTP/IMAP/submission stay on the container's own 25/143/587.
        # Reachable via Caddy on the LAN/mesh; NOT added to Cloudflare DNS
        # (a mail admin console shouldn't be on the public internet — do
        # that explicitly + behind CF Access if ever wanted).
        externalPort = 443;
        domain = "mail.kleinbem.dev";
        meta = {
          name = "Stalwart Mail";
          category = "Infrastructure";
          icon = "📬";
          description = "Persona-fleet mail server (SMTP/IMAP/JMAP).";
        };
      };
    };
  };
}
