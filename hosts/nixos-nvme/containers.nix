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
        containers = [
          "n8n"
          "code-server"
          "open-webui"
          "qdrant"
          "loki"
          "openclaw"
          "attic"
          "authelia"
          "github-runner"
          "ollama"
          "paperless"
          "backup"
          "syncthing"
          "cups"
          "crowdsec"
          "dashboard"
        ];
      };
      printing.enable = false; # Handled by the cups container
    };

    containers = {
      standaloneRunner = true;
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
        enable = true;
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
          myInventory.hosts.router-1.ip
          myInventory.hosts.router-2.ip
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

      caddy = {
        enable = lib.mkForce true;
        ip = "${myInventory.network.nodes.caddy.ip}/24";
        hostDataDir = "/var/lib/caddy";
        memoryLimit = "512M";
      };

      attic = {
        enable = false; # Handled by specialisations
        ip = "${myInventory.network.nodes.attic.ip}/24";
        hostDataDir = "/var/lib/images/attic";
        secretsFile = config.sops.templates."attic.env".path;
      };

      crowdsec = {
        enable = true;
        ip = "${myInventory.network.nodes.crowdsec.ip}/24";
        hostDataDir = "/var/lib/images/crowdsec";
      };

      netdata = {
        enable = false;
        ip = "${myInventory.network.nodes.netdata.ip}/24";
      };

      authelia = {
        enable = false;
        ip = "${myInventory.network.nodes.authelia.ip}/24";
        hostDataDir = "/var/lib/images/authelia";
        domain = "local";
      };

      cups = {
        enable = true;
        ip = "${myInventory.network.nodes.cups.ip}/24";
      };

      github-runner = {
        enable = false; # Moved to workload profiles
        ip = "${myInventory.network.nodes.github-runner.ip}/24";
        hostDataDir = "/var/lib/images/github-runner";
        secretsFile = config.sops.secrets.local_github_actions_runner.path;
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
        enable = true;
        ip = "10.85.46.128/24";
        passwordFile = config.sops.secrets.restic_password.path;
        systemPasswordFile = config.sops.secrets.restic_system_password.path;
        rcloneConfigFile = config.sops.secrets.rclone_config.path;
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
    "d /var/lib/images/github-runner 0755 1000 100 - -"
    "d /var/lib/images/syncthing 0755 root root - -"
  ];

  systemd.services = {
    # Caddy PKI: Copy the root CA cert to the user's home for Firefox trust
    # This runs on the host and is fail-safe to prevent restart loops.
    "container@caddy".postStart = ''
      SRC_CERT="/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt"
      if [ -f "$SRC_CERT" ]; then
        mkdir -p /home/${config.my.username}/.pki
        cp -f "$SRC_CERT" /home/${config.my.username}/.pki/caddy-root.crt
        chown ${config.my.username}:users /home/${config.my.username}/.pki/caddy-root.crt
        
        # Generate combined bundle for other services (e.g. github-runner) to trust local CA
        cat /etc/ssl/certs/ca-certificates.crt "$SRC_CERT" > /var/lib/caddy/ca-bundle.crt
        chmod 644 /var/lib/caddy/ca-bundle.crt
        
        echo "✅ Caddy Root CA copied and combined bundle generated."
      else
        echo "⚠️ Caddy Root CA not found at $SRC_CERT. Skipping copy."
      fi
    '';

    "container@crowdsec".preStart = ''
      mkdir -p /var/lib/images/crowdsec
      if [ ! -f /var/lib/images/crowdsec/bouncer-key ]; then
        tr -dc A-Za-z0-9 </dev/urandom | head -c 32 > /var/lib/images/crowdsec/bouncer-key
        chmod 600 /var/lib/images/crowdsec/bouncer-key
      fi
    '';
  };
}
