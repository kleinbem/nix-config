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
        # Auto-derive from actually-enabled containers (specialisations included),
        # minus an explicit exclude list. Avoids cron-time failures for containers
        # that aren't deployed on this host.
        containers =
          let
            excludeFromUpdater = [
              "caddy" # reverse proxy — restart briefly kills every other container's traffic
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
        enable = false;
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

      # Loki's home is nasbook: its inventory IP (10.85.47.116) is on nasbook's
      # .47 container subnet, which this host routes to 10.0.0.30 (nasbook), not
      # to cbr0 (.46). Enabling it here does NOT give fluent-bit a reachable
      # sink — the container comes up with that off-subnet IP and the host
      # routes traffic away to (currently-off) nasbook. Kept disabled; the
      # fluent-bit hardening in audit.nix makes the dead sink harmless, and
      # shipping resumes fleet-wide on its own once nasbook is back.
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

      authelia = {
        enable = false;
        ip = "${myInventory.network.nodes.authelia.ip}/24";
        hostDataDir = "/var/lib/images/authelia";
        domain = "local";
      };

      cups = {
        enable = false;
        ip = "${myInventory.network.nodes.cups.ip}/24";
      };

      github-runner = {
        enable = false; # Moved to workload profiles
        ip = "${myInventory.network.nodes.github-runner.ip}/24";
        hostDataDir = "/var/lib/images/github-runner";
        secretsFile = config.sops.secrets.github_runner_pat.path;
      };

      ollama = {
        enable = false; # Disabled by default; enabled in playground specialisation
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
        enable = false; # TEMP: toggle false→apply→true→apply to force NixOS to
        # cleanly tear down + recreate the container (its system was stuck stale).
        ip = "10.85.46.128/24";
        # Literal paths (not config.sops.secrets.*.path) on purpose: the sops
        # attribute evaluated to null inside the container's separate module
        # eval (mkContainer), which silently flipped restic to the /run/secrets/dummy
        # fallback. These are exactly what sops renders on the host, so the
        # read-only bind-mounts still point at the real secrets. See restic backup debug.
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
          "/var/lib/caddy" = "/var/lib/caddy";
          "/var/lib/images" = "/var/lib/images";
        };
      };

      paperless = {
        enable = false;
        ip = "${myInventory.network.nodes.paperless.ip}/24";
        hostDataDir = "/mnt/data/Archive/Paperless";
        hostConsumptionDir = "/mnt/data/Archive/Inbox";
        passwordFile = config.sops.secrets.paperless_password.path;
      };

      buzz = {
        # Re-enabled 2026-08-05: the 2026-08-02 SHIPPED-but-DISABLED IFD/
        # cross-arch bug (buzz-relay's cargoLock.lockFile = "${src}/Cargo.lock"
        # forced an eval-time realization of an x86_64-linux-pinned derivation,
        # which the aarch64 container-manifest promote runner couldn't build —
        # "platform mismatch", aborting manifest publish for every container
        # that cycle) is fixed: nix-presets/pkgs/buzz-relay.nix now points
        # cargoLock.lockFile at a vendored ./buzz-Cargo.lock instead of reading
        # the fetched source, so no IFD happens at eval time.
        enable = true;
        ip = "${myInventory.network.nodes.buzz.ip}/24";
        hostDataDir = "/var/lib/images/buzz";
        secretsFile = config.sops.templates."buzz.env".path;
        typesenseApiKeyFile = config.sops.secrets.buzz_typesense_api_key.path;
        # Reachable over NetBird mesh only for now — no public domain/Caddy
        # vhost set up yet. Switch to wss://buzz.kleinbem.dev once that's wired.
        relayUrl = "ws://${myInventory.network.nodes.buzz.ip}:3000";
      };

      # NOTE: the Stalwart persona-fleet mail server lives on mac-mini, not
      # here — nixos-nvme is a workstation, not a 24/7 host, and a mailserver
      # must always be up. See hosts/mac-mini/default.nix and
      # docs/PHASE1_STALWART_STATUS.md.
    };

  };

  # IMAGE STATE STORAGE
  systemd.tmpfiles.rules = [
    "d /var/lib/machines 0755 root root - -"
    "d /var/lib/machines/n8n 0755 root root - -"
    "d /var/lib/images 0755 root root - -" # Create parent, non-recursive
    "d /var/lib/images/n8n 0755 root root - -"
    "d /var/lib/images/playground 0755 martin users - -" # Ensure you own your playground
    "d /var/lib/images/caddy 0755 root root - -"
    "d /var/lib/images/litellm 0755 root root - -"
    "d /var/lib/images/loki 0755 root root - -"
    "d /var/lib/images/crowdsec 0755 root root - -"
    "d /var/lib/images/monitoring 0755 root root - -"
    "d /var/lib/images/monitoring/db 0755 root root - -"
    "d /var/lib/images/monitoring/grafana 0755 root root - -"
    "d /var/lib/images/qdrant 0755 root root - -"
    "d /var/lib/images/open-webui 0755 root root - -"
    "d /var/lib/images/lmstudio 0750 martin users - -"
    "d /var/lib/images/netdata 0755 root root - -"
    "d /var/lib/images/netdata/cache 0755 root root - -"
    "d /var/lib/images/netdata/lib 0755 root root - -"
    "d /var/lib/images/langfuse 0755 root root - -"
    "d /var/lib/images/langfuse/db 0755 root root - -"
    "d /var/lib/images/buzz 0755 root root - -"
    "d /var/lib/images/buzz/postgresql 0755 root root - -"
    "d /var/lib/images/buzz/redis 0755 root root - -"
    "d /var/lib/images/buzz/typesense 0755 root root - -"
    "d /var/lib/images/buzz/garage 0755 root root - -"
    "d /var/lib/images/buzz/relay 0755 root root - -"
    "d /var/lib/images/github-runner 0755 1000 100 - -"
    "d /var/lib/images/syncthing 0755 root root - -"
  ];

}
