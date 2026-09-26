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

  # ─── NetBird mesh groups ────────────────────────────────────
  # Membership for the NetBird control-plane groups managed by the
  # `nix/infra/netbird` OpenTofu root (groups.tf). This is the single
  # source of truth — the root reads it via the generated
  # `nix/infra/inventory.json` (see iac/data.nix). Until 2026-09-07 these
  # lists were duplicated as `variable ... { default = [...] }` blocks in
  # groups.tf, drifting silently from the fleet.
  #
  # Names must exist in `hosts` above (iac/data.nix asserts this). Peers
  # still self-register on the data plane (`netbird up`); this only drives
  # which control-plane group each enrolled peer lands in.
  meshGroups = {
    # Trusted personal machines — the only peers allowed to SSH infra and
    # use the buzz-relay route. Mirrors the `desktop`-tagged hosts.
    personal-devices = [
      "nixos-nvme"
      "mac-mini"
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
    # Node attrs: `public = true` puts the node's `domain` on the core-pi
    # Cloudflare Tunnel ingress (→ Caddy). Omit for mesh-only services —
    # `externalPort`/`auth` don't encode public vs mesh-only (code, frigate,
    # paperless, s3, … all have both yet stay on NetBird only).
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
        # homepage-dashboard (gethomepage/homepage) listens on 8082, not the
        # old custom skin's plain nginx :80 — Caddy's reverse_proxy
        # (nix-presets/containers/caddy/helpers.nix mkUpstream) reads this
        # field directly, so a stale value here is a silent 502.
        port = 8082;
        externalPort = 443; # Default HTTPS
        domain = "home.kleinbem.dev";
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
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
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
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
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
        mtls = true;
        auth = true; # Authentik forward-auth for the UI — was Authelia until 2026-09-22
        # Webhook endpoints are called by external services (GitHub, Stripe,
        # etc.) that can't complete an interactive Authentik login — carved
        # out of forward_auth at the Caddy layer (see caddy/helpers.nix).
        # This was ALSO true under Authelia (its access_control had no
        # path exclusion at all, blanket one_factor for *.kleinbem.dev) —
        # not a new gap introduced by the Authentik migration, just never
        # fixed until now.
        #
        # No network-layer auth on this path at all, deliberately — real
        # security has to be n8n's OWN per-webhook Header Auth/HMAC
        # signature verification (set per-workflow in n8n itself, not
        # something Nix/Terraform can configure). Didn't add a Cloudflare
        # WAF rate-limit rule here: the free plan's one rate-limit slot is
        # already spent on Vaultwarden (cloudflare-waf.tf), and a guessed
        # method/pattern restriction risks blocking real webhook payloads
        # without knowing this fleet's actual workflows. Worth adding once
        # the plan allows a second rule or the real traffic shape is known.
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
        # Corrected 2026-09-22: was "10.85.46.101", which never matched the
        # actually-running container (confirmed live via `machinectl status
        # code-server` on nixos-nvme, and a container-factory update pull
        # did NOT converge it — nspawn addresses are assigned once at
        # container creation, not re-applied on every closure activation).
        # This is the container's real, live address.
        ip = "10.85.46.22";
        port = 4444;
        externalPort = 443;
        domain = "code.kleinbem.dev";
        auth = true; # Mesh-only now — Cloudflare Access was its only gate; Authentik forward-auth replaces it (was Authelia until 2026-09-22)
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
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
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
        # Grafana's real listener, set via server.http_port in
        # nix-presets/containers/monitoring.nix. A stale `externalPort =
        # 3001` used to live here with nothing ever bound to it; the generic
        # `service-launchers` desktop entry prefers externalPort over port
        # when both exist, so it was silently pointing at a dead port.
        port = 3000;
        # Proxied through Caddy at grafana.kleinbem.dev (added 2026-09-19),
        # public tunnel ingress, no Cloudflare Access double-gate (see
        # nix/infra/cloudflare-access.tf's scope-decision comment).
        externalPort = 443;
        domain = "grafana.kleinbem.dev";
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
        # auth = false: Grafana logs visitors in itself via Authentik OIDC
        # (my.containers.monitoring.grafanaOidc on mac-mini, provider in
        # nix/infra/authentik.tf) instead of sitting behind Caddy's
        # forward_auth gate — avoids double-gating the same login. Was
        # `auth = true` / Authelia until the 2026-09-22 migration.
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
        # Runs inside the SAME monitoring container (containers/monitoring.nix
        # enables prometheus.alertmanager in the same innerConfig as
        # victoriametrics/grafana) — was pointing at 10.85.47.114 (nasbook's
        # subnet), a stale/wrong value predating this move, not something
        # that ever matched the container's real address. Fixed to match
        # monitoring's own IP above.
        ip = "10.85.50.2"; # mac-mini (moved from core-pi 2026-08-04)
        port = 9093;
        externalPort = 9093;
        # Added 2026-09-22 — forward_domain-mode forward-auth needs a real
        # *.kleinbem.dev hostname to match (bare IP:port never worked, see
        # nix/infra/netbird/dns.tf's mesh_only_fqdns). Mesh-only like
        # code-server/frigate, not on the public Cloudflare tunnel.
        domain = "alertmanager.kleinbem.dev";
        auth = true; # Authentik forward-auth (fleet_forward_auth Provider) — was Authelia until 2026-09-22
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
      # authelia removed 2026-09-22 — decommissioned, replaced by Authentik
      # forward-auth (nix/infra/authentik.tf's fleet_forward_auth Provider).
      # Freed: 10.85.48.123, authelia.kleinbem.dev.
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
        # Was 10.85.46.124 — a stale .46 (nixos-nvme's subnet) address that
        # never matched where cups actually deploys (core-pi, 10.85.48.0/24).
        # Same dual-IP/wrong-gateway bug as caddy/attic/crowdsec had — this
        # was the one instance of it left deliberately unfixed until now.
        # .123 was already freed (authelia's old slot, see comment below).
        ip = "10.85.48.123";
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
        # Added 2026-09-22 — forward_domain-mode forward-auth needs a real
        # *.kleinbem.dev hostname to match (bare IP:port never worked, see
        # nix/infra/netbird/dns.tf's mesh_only_fqdns). Mesh-only like
        # code-server/frigate, not on the public Cloudflare tunnel.
        domain = "syncthing.kleinbem.dev";
        auth = true; # Authentik forward-auth (fleet_forward_auth Provider) — was Authelia until 2026-09-22
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
        # Corrected 2026-09-22: was "10.85.46.130", which never matched the
        # actually-running container (confirmed live via `machinectl status
        # frigate` on orin-nano). This is the container's real, live
        # address. Note orin-nano's own cbr0 bridge reuses the same
        # 10.85.46.0/24 range as nixos-nvme's — they're separate host-local
        # L2 segments, not a shared subnet, so this is not a collision on
        # the wire, only for anything (like a single fleet-wide netbird
        # route or static LAN route) that tries to key purely off the /24.
        ip = "10.85.46.39";
        port = 5000;
        externalPort = 443;
        domain = "frigate.kleinbem.dev";
        auth = true; # Authentik forward-auth in front (was Authelia until 2026-09-22); mesh-only (NVR — never on the public tunnel)
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
        # Added 2026-09-22 — forward_domain-mode forward-auth needs a real
        # *.kleinbem.dev hostname to match (bare IP:port never worked, see
        # nix/infra/netbird/dns.tf's mesh_only_fqdns). Mesh-only like
        # code-server/frigate, not on the public Cloudflare tunnel.
        domain = "paperless.kleinbem.dev";
        auth = true; # Authentik forward-auth (fleet_forward_auth Provider) — was Authelia until 2026-09-22
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
        # Was auth.kleinbem.dev — a placeholder that happened to never
        # collide with anything until Authentik (whose preset explicitly
        # reserved that hostname) actually got deployed there. Renamed
        # 2026-09-21 rather than leave two Caddy vhosts fighting over one
        # domain (Caddy would refuse to start on the duplicate).
        domain = "2fa.kleinbem.dev";
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
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
        public = true; # tunnel ingress (modules/nixos/services/cloudflare-tunnel.nix)
        auth = false;
        meta = {
          name = "Vaultwarden";
          category = "Identity";
          icon = "🔐";
          description = "Self-hosted password manager (people + personas).";
        };
      };
      # kleinbem-auth removed 2026-09-21 — decommissioned, replaced by
      # Authentik below. login.kleinbem.dev is free again; 10.85.48.140
      # reused below by gatus.
      # Public fleet status page, probing the other public endpoints in
      # this file directly over HTTP (no Prometheus dependency). auth =
      # false: the whole point is a status page visitors can check without
      # signing in.
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
      # Shared IdP: replaces kleinbem-auth for kleinbem.dev visitor login and
      # also serves persona OIDC / Matrix federation / sigstore (the original
      # scope authentik.nix was built for) — one instance, multiple
      # Applications configured inside Authentik itself.
      # auth = false: this IS the sign-in surface — never Authelia-gated.
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
      # Persona-fleet mail (Phase 1). One mailbox per persona at
      # <name>@kleinbem.dev, created imperatively by persona-scaffold.sh.
      # Runs on mac-mini (24/7 host) — .50 subnet. Not Caddy-proxied —
      # SMTP/IMAP can't be Cloudflare-proxied; personas reach it directly
      # on this IP over the mesh. http/8080 (JMAP + webadmin) is the only
      # HTTP surface. See docs/PHASE1_STALWART_STATUS.md.
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
