{
  config,
  lib,
  myInventory,
  ...
}:

{
  my = {
    services = {
      container-updater = {
        enable = true;
        manifestUrl = "https://github.com/kleinbem/nix-config/releases/download/container-manifest/manifest.json";
        # Auto-derive from actually-enabled containers,
        # minus an explicit exclude list. Avoids cron-time failures for containers
        # that aren't deployed on this host.
        containers =
          let
            excludeFromUpdater = [
              "caddy" # reverse proxy — restart briefly kills every other container's traffic
              "github-runner" # opt-in debug runner — build embedded so `runners` cfg applies directly
            ];
            allEnabled = lib.attrNames (lib.filterAttrs (_: v: v.enable or false) config.my.containers);
          in
          lib.subtractLists excludeFromUpdater allEnabled;
      };
      printing.enable = true; # Re-enabled to restore local printer drivers
    };

    containers = {
      n8n = {
        enable = false;
        ip = "${myInventory.network.nodes.n8n.ip}/24";
        hostDataDir = "/var/lib/images/n8n";
        memoryLimit = "6G";
        secretsFile = config.sops.templates."n8n.env".path;
        noteDirs = {
          repos = config.my.developDir;
        };
        tls = {
          enable = true;
          serverPort = 5678;
          upstreams = [
            {
              name = "qdrant";
              target = myInventory.network.nodes.qdrant.ip;
              port = 6333;
            }
          ];
        };
      };

      code-server = {
        enable = true;
        ip = "${myInventory.network.nodes.code-server.ip}/24";
        hostDataDir = config.my.developDir;
        user = config.my.username;
        memoryLimit = "8G"; # IDEs are heavy
      };

      open-webui = {
        enable = false;
        ip = "${myInventory.network.nodes.open-webui.ip}/24";
        hostDataDir = "/var/lib/images/open-webui";
        memoryLimit = "4G";
        secretsFile = config.sops.templates."openwebui.env".path;
        tls = {
          enable = true;
          serverPort = 8080;
          upstreams = [
            {
              name = "langfuse";
              target = myInventory.network.nodes.langfuse.ip;
              port = 3000;
            }
          ];
        };
      };

      dashboard = {
        enable = false;
        ip = "${myInventory.network.nodes.dashboard.ip}/24";
        hostBridgeIp = myInventory.hosts.nixos-nvme.ip;
        memoryLimit = "1G";
        secretsFile = config.sops.templates."homepage.env".path;
      };

      qdrant = {
        enable = false;
        ip = "${myInventory.network.nodes.qdrant.ip}/24";
        hostDataDir = "/var/lib/images/qdrant";
        memoryLimit = "2G";
        tls = {
          enable = true;
          serverPort = 6333;
          upstreams = [ ];
        };
      };

      # Loki lives on nasbook: its inventory IP is on nasbook's .47 subnet,
      # which this host routes to nasbook, so enabling it here gives an
      # unreachable container.
      loki = {
        enable = false;
        ip = "${myInventory.network.nodes.loki.ip}/24";
        hostDataDir = "/var/lib/images/loki";
      };

      monitoring = {
        enable = false;
        ip = "${myInventory.network.nodes.monitoring.ip}/24";
        hostDataDir = "/var/lib/images/monitoring";
        nodeTargets = [
          myInventory.hosts.nixos-nvme.ip
          myInventory.hosts.core-gateway.ip
          myInventory.hosts.ap-upstairs.ip
        ];
        githubMetrics = {
          enable = true;
          repos = [ "kleinbem/nix" ];
          configFile = config.sops.templates."json-exporter.yml".path;
        };
      };

      openclaw = {
        enable = false;
        ip = "${myInventory.network.nodes.openclaw.ip}/24";
        hostDataDir = "/var/lib/images/openclaw";
      };

      netdata = {
        enable = true;
        ip = "${myInventory.network.nodes.netdata.ip}/24";
      };

      cups = {
        enable = false;
        ip = "${myInventory.network.nodes.cups.ip}/24";
      };

      # Debug runner, off unless needed. Excluded from container-updater, so it
      # builds on this host and `runners` applies directly. To use: add
      # `github_runner_pat` to nix/per-host/nixos-nvme.yaml, enable, apply, and
      # target `runs-on: [self-hosted, debug]`.
      github-runner = {
        enable = false;
        ip = "${myInventory.network.nodes.github-runner.ip}/24";
        hostDataDir = "/var/lib/images/github-runner";
        secretsFile = config.sops.secrets.github_runner_pat.path;
        runners.nix-config = {
          url = "https://github.com/kleinbem/nix-config";
          extraLabels = [
            "nixos"
            "debug"
          ];
        };
      };

      ollama = {
        enable = false;
        ip = "${myInventory.network.nodes.ollama.ip}/24";
        hostDataDir = "/var/lib/images/ollama";
      };

      syncthing = {
        enable = true;
        ip = "${myInventory.network.nodes.syncthing.ip}/24";
        hostDataDir = "/var/lib/images/syncthing";
        # secretsFile = config.sops.templates."syncthing.env".path;
        vaults = {
          "/home/${config.my.username}/Documents/Notes" = "/home/${config.my.username}/Documents/Notes";
          "/home/${config.my.username}/Develop" = "/home/${config.my.username}/Develop";
        };
      };

      backup = {
        enable = true;
        ip = "10.85.46.128/24";
        # Literal paths, not config.sops.secrets.*.path: that is null inside
        # the container's own module eval, which silently falls back to
        # /run/secrets/dummy.
        passwordFile = "/run/secrets/restic_password";
        systemPasswordFile = "/run/secrets/restic_system_password";
        rcloneConfigFile = "/run/secrets/rclone_config";
        targets = {
          "/home" = config.my.home;
          "/var/lib/images/n8n" = "/var/lib/images/n8n";
        };
        systemTargets = {
          "/etc/ssh" = "/etc/ssh";
          "/var/lib/sops" = "/var/lib/sops";
          "/nix/persist/var/lib/sbctl" = "/nix/persist/var/lib/sbctl";
        }
        # Only while the caddy container (ai.nix) exists to create its data
        # dir; a missing dir fails the whole backup container start.
        // lib.optionalAttrs config.my.containers.caddy.enable {
          "/var/lib/caddy" = "/var/lib/caddy";
        }
        # Per-app dirs, not /var/lib/images wholesale: the rest is model
        # weights, logs and caches, all regenerable. The preset's `exclude`
        # is built centrally, so narrow it here. Each dir must exist (see
        # tmpfiles.rules below) or the container fails to start.
        // lib.genAttrs [
          "/var/lib/images/open-webui"
          "/var/lib/images/qdrant"
          "/var/lib/images/monitoring"
          "/var/lib/images/langfuse"
          "/var/lib/images/langgraph"
          "/var/lib/images/buzz"
        ] (d: d);
      };

      paperless = {
        enable = false;
        ip = "${myInventory.network.nodes.paperless.ip}/24";
        hostDataDir = "/mnt/data/Archive/Paperless";
        hostConsumptionDir = "/mnt/data/Archive/Inbox";
        passwordFile = config.sops.secrets.paperless_password.path;
      };

      buzz = {
        enable = true;
        ip = "${myInventory.network.nodes.buzz.ip}/24";
        hostDataDir = "/var/lib/images/buzz";
        secretsFile = config.sops.templates."buzz.env".path;
        typesenseApiKeyFile = config.sops.secrets.buzz_typesense_api_key.path;
        # Through Caddy on core-pi (mesh only): Buzz 1.0 joins only over TLS.
        # The relay binds a community to one host, so this URL must match it.
        relayUrl = "wss://${myInventory.network.nodes.buzz.domain}";
        pairingRelayUrl = "wss://${myInventory.network.nodes.buzz.domain}/pair";
        # Members-only relay: required for mesh-llm compute sharing, which
        # takes its roster from the relay's NIP-43 membership snapshot.
        membership = {
          require = true;
          ownerPubkey = "5ce30e89348eb82870fde3213f25775f56f8a70a708ad2c9612118d7261ff936"; # Martin
          # No declared members: the owner is bootstrapped as a member by the relay,
          # and agents Buzz creates (Fizz, Pollen, Honey, ...) get in through their
          # owner attestation (NIP-OA, allowNipOaAuth). Other people join via invites.
          members = [ ];
        };
      };

      dev-db = {
        enable = true;
        ip = "${myInventory.network.nodes.dev-db.ip}/24";
        hostDataDir = "/var/lib/images/dev-db";
      };

      caido = {
        enable = true;
        ip = "${myInventory.network.nodes.caido.ip}/24";
        hostDataDir = "/var/lib/images/caido";
      };

      # Web UI for the host-native Garage (garage.nix, which also opens the
      # S3/admin ports to this container and renders garage-ui.env).
      garage-ui = {
        enable = true;
        ip = "${myInventory.network.nodes.garage-ui.ip}/24";
        hostDataDir = "/var/lib/images/garage-ui";
        secretsFile = config.sops.templates."garage-ui.env".path;
        oidc.enable = true;
      };
    };

  };

  # IMAGE STATE STORAGE
  systemd.tmpfiles.rules = [
    "d /var/lib/machines 0755 root root - -"
    "d /var/lib/machines/n8n 0755 root root - -"
    "d /var/lib/images 0755 root root - -" # Create parent, non-recursive
    "d /var/lib/images/n8n 0755 root root - -"
    "d /var/lib/images/playground 0755 martin users - -" # Ensure you own your playground
    # No caddy line: caddy/default.nix owns that dir (uid 3000).
    "d /var/lib/images/loki 0755 root root - -"
    "d /var/lib/images/crowdsec 0755 root root - -"
    "d /var/lib/images/monitoring 0755 root root - -"
    "d /var/lib/images/monitoring/db 0755 root root - -"
    # No monitoring/grafana line: monitoring.nix owns it (1000:100).
    "d /var/lib/images/qdrant 0755 root root - -"
    "d /var/lib/images/open-webui 0755 root root - -"
    "d /var/lib/images/lmstudio 0750 martin users - -"
    "d /var/lib/images/netdata 0755 root root - -"
    "d /var/lib/images/netdata/cache 0755 root root - -"
    "d /var/lib/images/netdata/lib 0755 root root - -"
    "d /var/lib/images/langfuse 0755 root root - -"
    "d /var/lib/images/langgraph 0755 root root - -"
    # No langfuse/db line: postgres needs uid 71, set in langfuse.nix.
    "d /var/lib/images/buzz 0755 root root - -"
    "d /var/lib/images/buzz/postgresql 0755 root root - -"
    "d /var/lib/images/buzz/redis 0755 root root - -"
    "d /var/lib/images/buzz/typesense 0755 root root - -"
    "d /var/lib/images/buzz/garage 0755 root root - -"
    "d /var/lib/images/buzz/relay 0755 root root - -"
    "d /var/lib/images/syncthing 0755 root root - -"
  ];

}
