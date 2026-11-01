let
  # ─── Tang NBDE Servers ──────────────────────────────────────
  # Every host runs Tang and is a clevis client of all the OTHERS (sss, t=1:
  # any one server unlocks). A host's own Tang isn't up during its own initrd
  # unlock, so lib/tang.nix leaves it out of that host's binding.
  # thp = SHA-256 thumbprint of the server's signing key; clevis verifies the
  # advertisement against it, so binding needs no trust prompt and can't be
  # redirected.
  tang = {
    nixos-nvme = {
      url = "http://10.0.0.5:7654";
      thp = "Zzi7JNtxV2LGgZVLxlJWo8xv1fVQaAgOy-2vKnJDRx8";
    };
    orin-nano = {
      url = "http://10.0.0.15:7654";
      thp = "UkXCd9RwLEKLDg46rFNuooViEpRO1Qy61kC3cuFuPZE";
    };
    core-pi = {
      url = "http://10.0.0.22:7654";
      thp = "jpULSo9iS7Cw9MjLWA9u7kIcHWyWDu3o1OtQCJcjQfM";
    };
    nasbook = {
      url = "http://10.0.0.30:7654";
      thp = "m_9W5Qh7Jo6a_c6dcSIVmTQhpL6tq27VoTWf6G5xhb0";
    };
    hass-pi = {
      url = "http://10.0.0.21:7654";
      thp = "3PlF5Uf9K64iCsOckD0N1sdGWzP5eeziibcKRz0xOSI";
    };
    mac-mini = {
      url = "http://10.0.0.16:7654";
      thp = "DUgzr8GGZH2CemMFsEgxg3ZD3-a59Zcx8IWrAYlfXzg";
    };
  };
in
{
  user = "martin";

  inherit tang;
  tangServers = map (t: t.url) (builtins.attrValues tang);

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
    # `board` picks the Ansible group (openwrt-config group_vars/board_<board>.yml)
    # and openwrt-builder profile: bpi-r4, orbi-rbr50, orbi-rbs50 (Orbi APs).
    # Orbi tags: `mesh-gate` = the RBR50 wired to a BPI-R4, `mesh-node` = the
    # RBS50 satellites on the 802.11s backhaul. Planned, add when flashed:
    #   ap-<location> = { ip = "10.0.0.3"; type = "openwrt"; board = "orbi-rbr50";
    #                     tags = [ "physical" "ap" "mesh-gate" ]; };
    #   ap-<location> = { ip = "10.0.0.4"; type = "openwrt"; board = "orbi-rbs50";
    #                     tags = [ "physical" "ap" "mesh-node" ]; };  # ×3 (.4 .6 .7)
    core-gateway = {
      ip = "10.0.0.1"; # Physical BPI-R4 (Main Gateway - Downstairs) — infra VLAN gateway
      type = "openwrt";
      board = "bpi-r4";
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
      board = "bpi-r4";
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
      ip = "10.0.0.21"; # Raspberry Pi
      netbirdIp = "100.117.163.227"; # Mesh IP (stable per enrollment)
      system = "aarch64-linux";
      deployType = "ssh";
      tags = [
        "raspberry-pi"
        "home-assistant"
      ];
    };
    phone = {
      # NetBird names peers after the device hostname; meshGroups use this.
      netbirdName = "xcoverpro2eea";
      system = "aarch64-linux";
      deployType = "local";
      tags = [
        "mobile"
        "android"
      ];
    };
    tablet = {
      # NetBird names peers after the Android device product (MRX-W09NM); meshGroups use this.
      netbirdName = "MRX-W09NM";
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
      ip = "10.0.0.16"; # LAN IP, static
      netbirdIp = "100.117.247.175"; # Mesh IP (stable per enrollment)
      system = "x86_64-linux"; # Mid-2011 Mac Mini (Macmini5,x) — Intel, real 64-bit EFI
      deployType = "ssh";
      tags = [
        "desktop"
        "legacy-hardware"
      ];
    };
  };

  # ─── NetBird mesh groups ────────────────────────────────────
  # Source of truth for NetBird group membership (nix/infra/netbird groups.tf,
  # via iac/data.nix). Names must exist in `hosts`. Peers still self-register;
  # this only picks the group each lands in.
  meshGroups = {
    # Trusted personal machines — the only peers allowed to SSH infra and
    # use the buzz-relay route. Mirrors the `desktop`-tagged hosts.
    personal-devices = [
      "nixos-nvme"
      "mac-mini"
      "phone"
      "tablet"
    ];
    # Smart-home / automation nodes (SSH-reachable from personal-devices).
    # nasbook isn't smart-home per se, but needs the same access this group
    # grants (cache-pull + SSH-reachable from personal-devices) and doesn't
    # warrant its own group for one host.
    smart-home = [
      "hass-pi"
      "orin-nano"
      "nasbook"
    ];
    # The attic/caddy cache entrypoint — exactly one host (the `central`
    # peer). CI runners may reach this and nothing else.
    cache = [ "core-pi" ];
  };

  git = {
    name = "kleinbem";
    # Must be a verified email on the GitHub account, or signed pushes to
    # protected branches fail. Switch once a kleinbem.dev mailbox is verified.
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
    # Node attrs: `public = true` puts the node's `domain` on the core-pi
    # Cloudflare Tunnel ingress (→ Caddy). Omit for mesh-only services —
    # `externalPort`/`auth` don't encode public vs mesh-only (code, frigate,
    # paperless, s3, … all have both yet stay on NetBird only).
    # `meshOnly = true` resolves `domain` + `extraDomains` to the Caddy peer
    # over NetBird DNS: iac/data.nix exports them to nix/infra/netbird/dns.tf,
    # and ai-hardening's dnsmasq forwards them to the NetBird agent.
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
        # homepage-dashboard's port. Caddy proxies to this field directly, so a
        # wrong value is a silent 502.
        port = 8082;
        externalPort = 443; # Default HTTPS
        domain = "home.kleinbem.dev";
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
        maintenance = false;
        auth = false; # Gated at the edge by Cloudflare Access (terraform/cloudflare-access.tf)
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
        meshOnly = true;
        # Being renamed to attic.kleinbem.dev, which frees cache.kleinbem.dev
        # for the public binary cache (R2). Both names work until every
        # host and CI job uses the new one.
        extraDomains = [ "attic.kleinbem.dev" ];
        # Mesh-only: every consumer reaches it over NetBird, the tunnel 413s on
        # large NARs, and the cache holds private sources. Pulls need a token.
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
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
        # No SSO: CI publishes the fleet-deploy signal with a plain curl and
        # devices long-poll anonymously; forward-auth would break both. Access
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
        meshOnly = true;
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
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
        mtls = true;
        auth = true; # Authentik forward-auth for the UI
        # Webhooks come from services that can't log in, so they skip
        # forward-auth. Each workflow must verify its own Header Auth/HMAC.
        # No WAF rate limit: the free plan's one slot is used by Vaultwarden.
        authExcludePaths = [
          "/webhook/*"
          "/webhook-test/*"
        ];
        meta = {
          name = "n8n Automation";
          category = "Apps";
          icon = "📡";
          description = "Workflow automation engine.";
        };
      };
      code-server = {
        # nspawn assigns the address at creation; changing it here doesn't
        # move a running container.
        ip = "10.85.46.22";
        port = 4444;
        externalPort = 443;
        domain = "code.kleinbem.dev";
        meshOnly = true;
        auth = true; # Authentik forward-auth
        meta = {
          name = "Code Server";
          category = "Dev";
          icon = "💻";
          description = "VS Code IDE in a hardened core container.";
        };
      };
      open-webui = {
        ip = "10.85.50.3"; # mac-mini
        port = 8080;
        externalPort = 443;
        domain = "chat.kleinbem.dev";
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
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
      langgraph = {
        ip = "10.85.46.111";
        port = 8123;
        externalPort = 8123;
        meta = {
          name = "LangGraph";
          category = "AI Engineering";
          icon = "🕸️";
          description = "Multi-agent graph runtime and API server. [AIRLOCK: Restricted Egress]";
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
        ip = "10.85.50.5"; # mac-mini
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
        ip = "10.85.50.7"; # mac-mini
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
        # publicCert: Buzz joins only over TLS with a public CA, so `tls internal`
        # won't do; Caddy gets a Let's Encrypt cert via DNS-01 while the name
        # stays mesh-only. /pair* goes to the pairing relay.
        domain = "buzz.kleinbem.dev";
        meshOnly = true;
        externalPort = 443;
        publicCert = true;
        extraRoutes."/pair*" = 3001;
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
        ip = "10.85.50.2"; # mac-mini
        port = 3000; # Grafana (server.http_port in nix-presets monitoring.nix)
        externalPort = 443;
        domain = "grafana.kleinbem.dev";
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
        # Grafana logs users in itself via Authentik OIDC; forward-auth on top
        # would gate the same login twice.
        auth = false;
        meta = {
          name = "Monitoring";
          category = "Infrastructure";
          icon = "📊";
          description = "VictoriaMetrics + Grafana Stack.";
        };
      };
      alertmanager = {
        enabled = true;
        # Runs inside the monitoring container, so same IP.
        ip = "10.85.50.2"; # mac-mini
        port = 9093;
        externalPort = 9093;
        # Forward-auth needs a real hostname; bare IP:port doesn't match.
        domain = "alertmanager.kleinbem.dev";
        meshOnly = true;
        auth = true; # Authentik forward-auth
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
      home-assistant = {
        ip = "10.85.49.10"; # Hass-Pi
        port = 8123;
        externalPort = 443;
        domain = "hass.kleinbem.dev";
        meshOnly = true;
        auth = false; # Home Assistant handles internal auth; forward-auth breaks mobile app
        meta = {
          name = "Home Assistant";
          category = "Apps";
          icon = "🏠";
          description = "Smart Home Automation.";
        };
      };

      cups = {
        ip = "10.85.48.123"; # core-pi
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
        ip = "10.85.47.127";
        port = 8384;
        externalPort = 8384;
        # Forward-auth needs a real hostname; bare IP:port doesn't match.
        domain = "syncthing.kleinbem.dev";
        meshOnly = true;
        auth = true; # Authentik forward-auth
        meta = {
          name = "Syncthing (Nasbook)";
          category = "Infrastructure";
          icon = "🔄";
          description = "File synchronization for the Fleet (Nasbook).";
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
        # orin-nano's cbr0 reuses nixos-nvme's 10.85.46.0/24. Separate L2
        # segments, but don't route fleet-wide by that /24 alone.
        ip = "10.85.46.39";
        # nginx from the NixOS frigate module; 5000 was never served.
        port = 80;
        externalPort = 443;
        domain = "frigate.kleinbem.dev";
        meshOnly = true;
        auth = true; # Authentik forward-auth; an NVR never goes on the public tunnel
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
        # Forward-auth needs a real hostname; bare IP:port doesn't match.
        domain = "paperless.kleinbem.dev";
        meshOnly = true;
        auth = true; # Authentik forward-auth
        meta = {
          name = "Paperless-ngx";
          category = "Documents";
          icon = "📄";
          description = "Document management system with OCR.";
        };
      };
      anythingllm = {
        ip = "10.85.50.6"; # mac-mini
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
        domain = "2fa-api.kleinbem.dev";
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
        auth = false;
        meta = {
          name = "Ente Auth API";
          category = "Identity";
          icon = "🔐";
          description = "E2E Encrypted 2FA Backend API.";
        };
      };
      ente-web = {
        ip = "10.85.48.133";
        port = 3003;
        externalPort = 443;
        domain = "2fa.kleinbem.dev";
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
        auth = false;
        meta = {
          name = "Ente Auth Web";
          category = "Identity";
          icon = "🔐";
          description = "E2E Encrypted 2FA Web Application.";
        };
      };
      # Self-hosted Bitwarden-compatible password vault for people + personas.
      # No forward-auth: it breaks the Bitwarden apps, CLI and extensions.
      # Vaultwarden's master password + 2FA is the gate, /admin by token.
      vaultwarden = {
        ip = "10.85.48.135";
        port = 8222;
        externalPort = 443;
        domain = "vault.kleinbem.dev";
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
        auth = false;
        meta = {
          name = "Vaultwarden";
          category = "Identity";
          icon = "🔐";
          description = "Self-hosted password manager (people + personas).";
        };
      };
      # Public status page probing the public endpoints here over HTTP.
      # No auth: visitors check it without signing in.
      gatus = {
        ip = "10.85.48.140";
        port = 8080;
        externalPort = 443;
        domain = "status.kleinbem.dev";
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
        auth = false;
        meta = {
          name = "Status";
          category = "Infrastructure";
          icon = "🟢";
          description = "Fleet uptime / status page.";
        };
      };
      # Shared IdP: visitor login, persona OIDC, Matrix, sigstore.
      # No auth: this is the sign-in surface itself.
      authentik = {
        ip = "10.85.48.142";
        port = 9000;
        externalPort = 443;
        domain = "auth.kleinbem.dev";
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
        auth = false;
        meta = {
          name = "Authentik";
          category = "Identity";
          icon = "🪪";
          description = "Shared identity provider (SSO, social login, persona OIDC).";
        };
      };
      # Persona mail on mac-mini; persona-scaffold.sh creates the mailboxes.
      # SMTP/IMAP can't go through Cloudflare, so personas reach this IP over
      # the mesh directly.
      stalwart = {
        ip = "10.85.50.8";
        port = 8080;
        # Caddy proxies only the JMAP/webadmin HTTP surface, LAN/mesh only:
        # a mail admin console stays off public DNS.
        externalPort = 443;
        domain = "mail.kleinbem.dev";
        meta = {
          name = "Stalwart Mail";
          category = "Infrastructure";
          icon = "📬";
          description = "Persona-fleet mail server (SMTP/IMAP/JMAP).";
        };
      };
      # Git forge next to GitHub (nix-presets containers/forgejo.nix): mirrors
      # first, private repos later. Logs in through Authentik OIDC itself, so
      # no forward-auth gate. Mesh only, through Caddy; Git goes over HTTPS.
      # SSH stays off until it has its own name and a DNAT on mac-mini, since
      # this domain resolves to Caddy, not to the container.
      forgejo = {
        ip = "10.85.50.4";
        port = 3000;
        externalPort = 443;
        domain = "git.kleinbem.dev";
        meshOnly = true;
        auth = false;
        meta = {
          name = "Forgejo";
          category = "Dev";
          icon = "🌳";
          description = "Self-hosted Git forge with mirrors of the GitHub repos.";
        };
      };
      dev-db = {
        ip = "10.85.46.132"; # nixos-nvme bridge
        port = 5432;
        meta = {
          name = "Dev Database";
          category = "Dev";
          icon = "🗄️";
          description = "Shared PostgreSQL 17 & Redis instance for devshells.";
        };
      };
      caido = {
        ip = "10.85.46.133"; # nixos-nvme bridge
        port = 8080;
        domain = "caido.kleinbem.dev";
        meta = {
          name = "Caido Security";
          category = "Security";
          icon = "🛡️";
          description = "Headless web security proxy & auditing daemon.";
        };
      };
      garage-ui = {
        ip = "10.85.46.134"; # nixos-nvme bridge, next to host-native Garage
        port = 8080;
        externalPort = 443;
        domain = "garage.kleinbem.dev";
        meshOnly = true;
        # Mesh-only (no public tunnel). auth = false: the UI logs users in
        # itself via Authentik OIDC (oidc_apps in nix/infra/authentik.tf),
        # same as Grafana, instead of Caddy's forward_auth gate.
        auth = false;
        meta = {
          name = "Garage UI";
          category = "Infrastructure";
          icon = "🪣";
          description = "Web dashboard for Garage S3: buckets, objects, keys, layout.";
        };
      };
      qbittorrent = {
        ip = "10.85.47.134"; # nasbook subnet
        port = 8080;
        domain = "torrents.kleinbem.dev";
        meshOnly = true;
        meta = {
          name = "qBittorrent";
          category = "Apps";
          icon = "📥";
          description = "Headless torrent downloader with WebUI.";
        };
      };
      miniflux = {
        ip = "10.85.47.135"; # nasbook subnet
        port = 8080;
        externalPort = 443;
        domain = "news.kleinbem.dev";
        public = true;
        auth = false; # Miniflux provides its own user authentication & API keys
        meta = {
          name = "Miniflux";
          category = "Media";
          icon = "📰";
          description = "Minimalist and opinionated feed reader.";
        };
      };
    };
  };
}
