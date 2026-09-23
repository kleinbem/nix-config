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

    # NOT enabled — monitoring already lives on mac-mini (moved there
    # 2026-08-04 for RAM headroom) and this exact option is ALSO declared
    # `enable = false` in this host's own containers.nix (hosts/nixos-nvme/
    # containers.nix:111) — a leftover duplicate stub from before ai.nix
    # was split out. Flipping either copy to `true` without reconciling
    # the other throws a conflicting-definition eval error (confirmed
    # 2026-08-19), and even if forced, it'd stand up a second Grafana/
    # Prometheus instance fighting mac-mini's for the same
    # myInventory.network.nodes.monitoring.ip. Needs the duplicate
    # removed (probably drop the containers.nix stub) before this can be
    # touched again.
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

  # The rest of this host's container data dirs used to all get a blanket
  # `0777 root root` here — a shortcut that both made several of them
  # world-writable for no reason (litellm and the langfuse app container
  # don't even write to their hostDataDir; playground's factory default of
  # 0755 1000:100 already matches its container's uid=1000 user) and
  # actively conflicted with correct rules the owning preset already
  # declares (caddy's own `Z ... 0755 3000 3000`, monitoring's own
  # `0755 1000 100` for its grafana subdir). comfyui/langflow now pin their
  # podman containers to run as 1000:100 and get a matching tmpfiles rule
  # in their own preset; langfuse-db's postgres data dir gets the real
  # postgres uid/gid via dataDirOwner/dataDirGroup in langfuse.nix. The
  # `/var/lib/images/ollama` rules referenced a host user ("ollama") that
  # doesn't exist on this host — services.ollama isn't configured here,
  # only the nspawn `my.containers.ollama` in containers.nix, whose own
  # process runs as root and needs no dir override — so those two lines
  # were simply broken and are dropped, not replaced.
  systemd.tmpfiles.rules = [
    "d /var/lib/images/agent-team 0755 1000 100 - -"
    "d /var/lib/images/agent-team/workspace 0775 1000 100 - -"
    "d /var/lib/images/agent-team/state 0700 1000 100 - -"
    "d /var/lib/images/podman/tmp 1777 root root - -"
  ];

}
