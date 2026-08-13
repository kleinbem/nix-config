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
let
  caddyPortsList = [
    80
    443
  ]
  ++ (lib.mapAttrsToList (_: node: node.externalPort) (
    lib.filterAttrs (_: v: v ? externalPort) myInventory.network.nodes
  ));
  caddyPortsStr = lib.concatMapStringsSep ", " toString (lib.unique caddyPortsList);
in
{
  imports = [
    "${self}/modules/nixos/rpi5-node.nix"
    "${self}/modules/nixos/container-host.nix"
    "${self}/modules/nixos/services/container-updater.nix"
    ./disko.nix
    ./secrets.nix
    inputs.nix-presets.nixosModules.dashboard
    inputs.nix-presets.nixosModules.ente
    inputs.nix-presets.nixosModules.cups
    inputs.nix-presets.nixosModules.github-runner
    inputs.nix-presets.nixosModules.authelia
    inputs.nix-presets.nixosModules.attic
    inputs.nix-presets.nixosModules.ntfy
    inputs.nix-presets.nixosModules.caddy
    inputs.nix-presets.nixosModules.crowdsec
    inputs.nix-presets.nixosModules.herdr-remote-client
    "${self}/modules/nixos/services/cloudflare-tunnel.nix"
  ];

  # Additive to rpi5-node.nix's martin.openssh.authorizedKeys.keys (list
  # options merge across modules) — scoped here rather than there because
  # this key only makes sense on the one host that actually runs Caddy.
  # See modules/nixos/keys.nix for why it's a plain unattended key rather
  # than one of the FIDO2 ones every other authorizedKeys entry here uses.
  users.users.martin.openssh.authorizedKeys.keys = [
    (import "${self}/modules/nixos/keys.nix").ssh.caddy-ca-refresh
  ];

  networking = {
    hostName = "core-pi";

    # ─── Firewall and NAT for Caddy ──────────────────────────────
    nftables = {
      enable = true;
      tables.netbird-nat = {
        family = "inet";
        content = ''
          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;
            iifname "wt0" tcp dport { ${caddyPortsStr} } dnat ip to ${myInventory.network.nodes.caddy.ip}
          }
        '';
      };
    };

    firewall = {
      # Open all ports that Caddy is proxying to allow external access
      allowedTCPPorts = lib.unique caddyPortsList;
      interfaces."wt0".allowedTCPPorts = [ 22 ] ++ lib.unique caddyPortsList;
      interfaces."end0".allowedTCPPorts = [ 7654 ]; # Tang
      extraForwardRules = ''
        # Allow NetBird traffic that was NAT'd to reach the Caddy container
        iifname "wt0" oifname "${myInventory.network.bridge}" ip daddr ${myInventory.network.nodes.caddy.ip} tcp dport { ${caddyPortsStr} } accept
      '';
    };
  };

  my = {
    # ─── Clevis LUKS & Network Identity ─────────────────────────
    boot.clevis-initrd = {
      enable = true;
      luksDevice = "core_crypt";
      hostIp = "10.0.0.22";
      secretFile = "${inputs.nix-secrets}/initrd/cryptroot_core-pi.jwe";
    };

    herdr-remote-client = {
      enable = true;
      serverIp = "10.0.0.5"; # nixos-nvme physical LAN IP (inventory.nix)
    };

    # ─── Container Hosting (via reusable module) ────────────────
    container-host = {
      enable = true;
      subnet = "10.85.48.0/24";
      hostAddress = "10.85.48.1";
      excludeFromUpdater = [
        "attic"
        "caddy"
        "crowdsec"
      ];
    };

    services.tang.enable = true;

    # ─── Containers ──────────────────────────────────────────────
    containers = {
      caddy = {
        enable = lib.mkForce true;
        ip = "${myInventory.network.nodes.caddy.ip}/24";
        hostDataDir = "/var/lib/caddy";
        memoryLimit = "512M";
        # kleinbem.dev — static Astro build (kleinbem/kleinbem-site), packaged
        # in nix-packages. hostPath is a Nix store path: every switch that
        # picks up a newer kleinbem-site build re-points the bind-mount at
        # the new output, no manual redeploy step.
        staticSites."kleinbem.dev" = {
          hostPath = "${pkgs.kleinbem-site}";
        };
      };

      crowdsec = {
        enable = true;
        ip = "${myInventory.network.nodes.crowdsec.ip}/24";
        hostDataDir = "/var/lib/images/crowdsec";
      };

      # Fleet-deploy signal (promote-production → nixos-upgrade-listener).
      # Lives here, not on the workstation: core-pi already fronts the public
      # path (cloudflared + caddy) and is always on.
      ntfy = {
        enable = true;
        ip = "${myInventory.network.nodes.ntfy.ip}/24";
      };

      ente = {
        enable = true;
        ip = "${myInventory.network.nodes.ente.ip}/24";
        hostDataDir = "/var/lib/ente";
      };

      dashboard = {
        enable = true;
        ip = "${myInventory.network.nodes.dashboard.ip}/24";
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
        # atticd marks superseded chunks deleted but never unlinks them here;
        # weekly reaper reclaims the dead files (Sun 05:30, post-autoUpgrade).
        autoReap.enable = true;
      };

    };

    # This host IS the cache entrypoint: its own pulls must go straight to the
    # local caddy container — traffic to its own NetBird IP never traverses the
    # wt0 PREROUTING DNAT (see modules/nixos/attic-pull.nix).
    atticPull.cacheHostIp = myInventory.network.nodes.caddy.ip;

    # ─── Container auto-update (ADR 002) ────────────────────────
    # Configured via container-host module's excludeFromUpdater list (see above).
    # Containers are decoupled from the host generation and refreshed nightly
    # from the CI-published manifest — eval-free on the Pi.
  };

  # ─── Persistence (Additional) ───────────────────────────────
  # container-host module handles container data persistence
  # (auto-derived from each enabled container's hostDataDir, incl.
  # /var/lib/ente). Add only non-container directories here.

  # kleinbem.dev static site bind-mount, wired here (a real, separate
  # `containers.caddy.bindMounts` definition) rather than through
  # my.containers.caddy.staticSites' own wiring — that path is dead:
  # nix-presets/containers/caddy/default.nix combines
  # `lib.mkIf (hostDataDir != null) {...}` with plain `//`, and since
  # mkIf's result carries a `_type = "if"` marker, the module system's
  # dischargeProperties collapses the WHOLE merged value down to just that
  # mkIf's own `content` (`/var/lib/caddy`), silently dropping everything
  # merged in after it — including the module's own PKI-cert mounts, which
  # means those have likely never actually applied either. Not fixed here:
  # that's shared code fronting every live public service on this host —
  # fix it in nix-presets separately, verify the PKI-cert host paths
  # actually exist first, then this workaround (and the
  # my.containers.caddy.staticSites option's own bindMounts logic) can be
  # revisited. The staticSites option itself still IS used above, for the
  # Caddy vhost it generates (that half of the module isn't affected by
  # this bug).
  containers.caddy.bindMounts."/var/www/kleinbem.dev" = {
    hostPath = "${pkgs.kleinbem-site}";
    isReadOnly = true;
  };

  services.crowdsec-firewall-bouncer = {
    enable = true;
    secrets.apiKeyPath = "/var/lib/images/crowdsec/bouncer-key";
    settings = {
      api_url = "http://${myInventory.network.nodes.crowdsec.ip}:8080/";
      api_keyfile = "/var/lib/images/crowdsec/bouncer-key";
    };
  };

  systemd.services = {
    crowdsec-firewall-bouncer = {
      after = [ "container@crowdsec.service" ];
      wants = [ "container@crowdsec.service" ];
      preStart = ''
        until ${pkgs.curl}/bin/curl -s http://${myInventory.network.nodes.crowdsec.ip}:8080/ > /dev/null; do
          echo "Waiting for CrowdSec LAPI..."
          sleep 2
        done
      '';
    };

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
