# core-pi — Raspberry Pi 5 (AI & Infrastructure Services)
{
  config,
  lib,
  pkgs,
  inputs,
  self,
  myInventory,
  ...
}:
{
  imports = [
    "${self}/modules/nixos/rpi5-node.nix"
    "${self}/modules/nixos/services/container-updater.nix"
    ./disko.nix
    ./secrets.nix
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.anythingllm
    inputs.nix-presets.nixosModules.dashboard
    inputs.nix-presets.nixosModules.cups
    inputs.nix-presets.nixosModules.github-runner
    inputs.nix-presets.nixosModules.authelia
    inputs.nix-presets.nixosModules.attic
    inputs.nix-presets.nixosModules.monitoring
    inputs.nix-presets.nixosModules.caddy
    inputs.nix-presets.nixosModules.crowdsec
    "${self}/modules/nixos/services/cloudflare-tunnel.nix"
  ];

  networking.hostName = "core-pi";

  my = {
    # ─── Clevis LUKS & Network Identity ─────────────────────────
    boot.clevis-initrd = {
      enable = true;
      luksDevice = "core_crypt";
      hostIp = "10.0.0.22";
      secretFile = "${./cryptroot.jwe}";
    };

    # ─── Container Network ──────────────────────────────────────
    network = {
      subnet = "10.85.48.0/24";
      hostAddress = "10.85.48.1";
    };

    services.tang.enable = true;

    # ─── Containers ──────────────────────────────────────────────
    containers = {
      caddy = {
        enable = lib.mkForce true;
        ip = "${myInventory.network.nodes.caddy.ip}/24";
        hostDataDir = "/var/lib/caddy";
        memoryLimit = "512M";
      };

      crowdsec = {
        enable = true;
        ip = "${myInventory.network.nodes.crowdsec.ip}/24";
        hostDataDir = "/var/lib/images/crowdsec";
      };

      open-webui = {
        enable = true;
        ip = "${myInventory.network.nodes.open-webui.ip}/24";
        hostDataDir = "/var/lib/open-webui";
        memoryLimit = "2G";
      };

      openclaw = {
        enable = true;
        ip = "${myInventory.network.nodes.openclaw.ip}/24";
        hostDataDir = "/var/lib/openclaw";
        memoryLimit = "1G";
      };

      agent-zero = {
        enable = true;
        ip = "${myInventory.network.nodes.agent-zero.ip}/24";
        hostDataDir = "/var/lib/agent-zero";
        memoryLimit = "1G";
      };

      anythingllm = {
        enable = true;
        ip = "${myInventory.network.nodes.anythingllm.ip}/24";
        hostDataDir = "/var/lib/anythingllm";
        llmUrl = "https://litellm.internal";
        modelName = "google/gemma-2b"; # Aligned with Orin Nano backend in ai.nix
        memoryLimit = "2G";
      };

      dashboard = {
        enable = true;
        ip = "10.85.48.103/24";
        hostBridgeIp = "10.0.0.22"; # core-pi IP
        memoryLimit = "512M";
      };

      cups = {
        enable = true;
        ip = "${myInventory.network.nodes.cups.ip}/24";
      };

      github-runner = {
        enable = false; # Disabled until core-pi is physically online
        ip = "${myInventory.network.nodes.github-runner.ip}/24"; # Need to ensure this doesn't conflict if nvme also runs one
        hostDataDir = "/var/lib/github-runner";
        # secretsFile = config.sops.secrets.github_runner_pat.path;
      };

      authelia = {
        enable = true;
        ip = "${myInventory.network.nodes.authelia.ip}/24";
        hostDataDir = "/var/lib/images/authelia";
        domain = "local";
      };

      attic = {
        enable = true;
        ip = "${myInventory.network.nodes.attic.ip}/24";
        hostDataDir = "/var/lib/images/attic";
        secretsFile = config.sops.templates."attic.env".path;
      };

      monitoring = {
        enable = true;
        ip = "10.85.48.114/24";
        hostDataDir = "/var/lib/monitoring";
        nodeTargets = [
          myInventory.hosts.nixos-nvme.ip
          myInventory.hosts.router-1.ip
          myInventory.hosts.router-2.ip
          myInventory.hosts.core-pi.ip
          myInventory.hosts.hass-pi.ip
        ];
        githubMetrics.enable = false;
      };
    };

    # This host IS the cache entrypoint: its own pulls must go straight to the
    # local caddy container — traffic to its own NetBird IP never traverses the
    # wt0 PREROUTING DNAT (see modules/nixos/attic-pull.nix).
    atticPull.cacheHostIp = myInventory.network.nodes.caddy.ip;

    # ─── Standalone container auto-update (ADR 002) ─────────────
    # Same model as nixos-nvme: containers are decoupled from the host
    # generation and refreshed nightly from the CI-published manifest —
    # eval-free on the Pi. The bulk updater stages everything first and
    # activates attic LAST so the cache keeps serving mid-update.
    services.container-updater = {
      enable = true;
      # Exclude critical infrastructure from the nightly decoupled updates.
      # core-pi uses impermanence, so /var/lib/machines is wiped on reboot.
      # If attic/caddy are decoupled, they must be downloaded from the cache
      # at boot, but the cache IS attic/caddy, creating a bootstrap deadlock.
      # By excluding them, they are built into the host closure and start reliably.
      containers =
        let
          excludeFromUpdater = [
            "attic"
            "caddy"
            "crowdsec"
          ];
          allEnabled = lib.attrNames (lib.filterAttrs (_: v: v.enable or false) config.my.containers);
        in
        lib.subtractLists excludeFromUpdater allEnabled;
    };
  };

  # ─── Persistence ─────────────────────────────────────────────
  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/open-webui"
      "/var/lib/openclaw"
      "/var/lib/agent-zero"
      "/var/lib/anythingllm"
      "/var/lib/monitoring"
    ];
  };

  # ─── Firewall and NAT for Caddy ──────────────────────────────
  networking.nftables = {
    enable = true;
    tables.netbird-nat = {
      family = "inet";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          iifname "wt0" tcp dport { 80, 443 } dnat ip to ${myInventory.network.nodes.caddy.ip}
        }
      '';
    };
  };

  networking.firewall = {
    # Open all ports that Caddy is proxying to allow external access
    allowedTCPPorts = lib.mapAttrsToList (_: node: node.externalPort) (
      lib.filterAttrs (_: v: v ? externalPort) myInventory.network.nodes
    );
    interfaces."wt0".allowedTCPPorts = [
      22 # SSH
      443 # Caddy HTTPS (access all services via reverse proxy)
    ];
    interfaces."end0".allowedTCPPorts = [ 7654 ]; # Tang
    extraForwardRules = ''
      # Allow NetBird traffic that was NAT'd to reach the Caddy container
      iifname "wt0" oifname "${myInventory.network.bridge}" ip daddr ${myInventory.network.nodes.caddy.ip} tcp dport { 80, 443 } accept
    '';
  };

  services.crowdsec-firewall-bouncer = {
    enable = true;
    secrets.apiKeyPath = "/var/lib/images/crowdsec/bouncer-key";
    settings = {
      api_url = "http://${myInventory.network.nodes.crowdsec.ip}:8080/";
      api_keyfile = "/var/lib/images/crowdsec/bouncer-key";
    };
  };

  systemd.services.crowdsec-firewall-bouncer = {
    after = [ "container@crowdsec.service" ];
    wants = [ "container@crowdsec.service" ];
    preStart = ''
      until ${pkgs.curl}/bin/curl -s http://${myInventory.network.nodes.crowdsec.ip}:8080/ > /dev/null; do
        echo "Waiting for CrowdSec LAPI..."
        sleep 2
      done
    '';
  };

  systemd.services = {
    "container@caddy".postStart = ''
      SRC_CERT="/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt"
      if [ -f "$SRC_CERT" ]; then
        mkdir -p /home/${config.my.username}/.pki
        cp -f "$SRC_CERT" /home/${config.my.username}/.pki/caddy-root.crt
        chown ${config.my.username}:users /home/${config.my.username}/.pki/caddy-root.crt
        
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
