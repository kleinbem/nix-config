# core-pi — Raspberry Pi 5 (AI & Infrastructure Services)
{
  config,
  lib,
  pkgs,
  inputs,
  self,
  myInventory,
  secretFile,
  ...
}:
let
  # Single source of truth for this host's LUKS volume name — feeds both
  # rpi5-disko.nix (via _module.args below) and my.boot.clevis-initrd.
  luksVolumeName = "core_crypt";

  caddyPortsList = [
    80
    443
  ]
  ++ (lib.mapAttrsToList (_: node: node.externalPort) (
    lib.filterAttrs (_: v: v ? externalPort) myInventory.network.nodes
  ));
  caddyPortsStr = lib.concatMapStringsSep ", " toString (lib.unique caddyPortsList);

  # Real fleet-specific endpoint list for the gatus preset's endpointsFile
  # (bind-mounted into the container at runtime — see nix-presets'
  # containers/gatus.nix for why this can't be baked into the preset
  # itself: container-factory builds that closure once, centrally).
  gatusEndpointsFile = (pkgs.formats.yaml { }).generate "gatus-endpoints.yaml" {
    endpoints = [
      {
        name = "kleinbem.dev";
        group = "Public";
        url = "https://kleinbem.dev";
        interval = "3m";
        conditions = [
          "[STATUS] < 500"
          "[RESPONSE_TIME] < 3000"
        ];
      }
      {
        name = "Dashboard";
        group = "Public";
        url = "https://home.kleinbem.dev";
        interval = "3m";
        conditions = [ "[STATUS] < 500" ];
      }
      {
        # Through Caddy on this host to the container on hass-pi. HA answers
        # its login page unauthenticated, so a 200 proves the whole path.
        name = "Home Assistant";
        group = "Apps";
        url = "https://hass.kleinbem.dev";
        interval = "3m";
        conditions = [ "[STATUS] < 500" ];
      }
      {
        name = "Vaultwarden";
        group = "Identity";
        url = "https://vault.kleinbem.dev";
        interval = "3m";
        conditions = [ "[STATUS] < 500" ];
      }
      {
        # museum's own liveness endpoint, end to end through the tunnel.
        name = "Ente Auth API";
        group = "Identity";
        url = "https://2fa-api.kleinbem.dev/ping";
        interval = "3m";
        conditions = [
          "[STATUS] == 200"
          "[BODY].message == pong"
        ];
      }
      {
        name = "Ente Auth Web";
        group = "Identity";
        url = "https://2fa.kleinbem.dev";
        interval = "3m";
        conditions = [ "[STATUS] == 200" ];
      }
      {
        name = "Authentik";
        group = "Identity";
        # Not `/` or /-/health/*: those answer even when the Django server
        # behind the Rust front is down. This endpoint only returns 200 when
        # the real server is serving.
        url = "https://auth.kleinbem.dev/api/v3/root/config/";
        interval = "3m";
        conditions = [
          "[STATUS] == 200"
          "[RESPONSE_TIME] < 3000"
        ];
      }
      {
        name = "Grafana";
        group = "Infrastructure";
        url = "https://grafana.kleinbem.dev";
        interval = "3m";
        conditions = [ "[STATUS] < 500" ];
      }
      {
        name = "ntfy";
        group = "Infrastructure";
        url = "https://ntfy.kleinbem.dev";
        interval = "3m";
        conditions = [ "[STATUS] < 500" ];
      }
      {
        name = "Attic cache";
        group = "Infrastructure";
        url = "https://cache.kleinbem.dev";
        interval = "3m";
        conditions = [ "[STATUS] < 500" ];
      }
      {
        name = "n8n";
        group = "Apps";
        url = "https://n8n.kleinbem.dev";
        interval = "3m";
        conditions = [ "[STATUS] < 500" ];
      }
      {
        name = "Chat";
        group = "Apps";
        url = "https://chat.kleinbem.dev";
        interval = "3m";
        conditions = [ "[STATUS] < 500" ];
      }
    ];
  };
in
{
  imports = [
    "${self}/modules/nixos/rpi5-node.nix"
    inputs.nix-gantry.nixosModules.host
    inputs.nix-gantry.nixosModules.host-persistence
    inputs.nix-gantry.nixosModules.updater
    "${self}/modules/nixos/rpi5-disko.nix"
    ./secrets.nix
    inputs.nix-presets.nixosModules.dashboard-homepage
    inputs.nix-presets.nixosModules.ente
    inputs.nix-presets.nixosModules.vaultwarden
    inputs.nix-presets.nixosModules.gatus
    inputs.nix-presets.nixosModules.authentik
    inputs.nix-presets.nixosModules.cups
    inputs.nix-presets.nixosModules.attic
    inputs.nix-presets.nixosModules.ntfy
    inputs.nix-presets.nixosModules.caddy
    inputs.nix-presets.nixosModules.crowdsec
    inputs.nix-presets.nixosModules.herdr-remote-client
    "${self}/modules/nixos/services/cloudflare-tunnel.nix"
  ];

  _module.args.luksName = luksVolumeName;

  # Adds to rpi5-node.nix's keys; only this host runs Caddy. keys.nix
  # explains why it's a plain unattended key, not FIDO2.
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
      # Without backend + filterForward, extraForwardRules below (and
      # container-host.nix's bridge-accept fragment) are silently ignored.
      backend = "nftables";
      filterForward = true;
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
    # External dead-man's switch (modules/nixos/heartbeat.nix): <host>-alive
    # every 5 min + a ping per backup job; missing pings alert from
    # healthchecks.io, outside the fleet. Always-on hosts only.
    heartbeat.enable = true;
    # comin pull-deploy (modules/nixos/comin.nix) follows the signed production
    # branch. requireCache: this host never compiles a closure, CI builds its
    # toplevel before promote moves the branch.
    deploy = {
      autoUpgrade.enable = false;
      comin = {
        enable = true;
        requireCache = true;
      };
    };
    # ─── Clevis LUKS & Network Identity ─────────────────────────
    boot.clevis-initrd = {
      enable = true;
      luksDevice = luksVolumeName;
      hostIp = "10.0.0.22";
      secretFile = secretFile "initrd/cryptroot_core-pi.jwe";
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
      manifestUrl = "https://github.com/kleinbem/nix-config/releases/download/container-manifest/manifest.json";
      # nix-gantry defaults this off to avoid requiring impermanence; this
      # fleet always imports it.
      enablePersistence = true;
      excludeFromUpdater = [
        "attic"
        "caddy"
        "crowdsec"
      ];
    };

    services = {
      tang.enable = true;
      cloudflareTunnel.enable = true;
    };

    # Fleet wiring in modules/nixos/backup.nix. vaultwarden, authentik, ente,
    # caddy (local CA) and tang register their own items. R2 credentials come
    # from backup_r2_rclone_config in nix/per-host/core-pi.yaml.
    backup.enable = true;

    # ─── Containers ──────────────────────────────────────────────
    containers = {
      caddy = {
        enable = lib.mkForce true;
        ip = "${myInventory.network.nodes.caddy.ip}/24";
        hostIP = myInventory.network.nodes.caddy.ip;
        proxyTargets = lib.filterAttrs (_: v: v ? externalPort) myInventory.network.nodes;
        globalMaintenance = myInventory.globalMaintenance or false;
        hostDataDir = "/var/lib/caddy";
        memoryLimit = "512M";
        # CLOUDFLARE_API_TOKEN for publicCert vhosts (secrets.nix).
        secretsFile = lib.mkIf (lib.any (n: n.publicCert or false) (
          lib.attrValues myInventory.network.nodes
        )) config.sops.templates."caddy.env".path;
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
        # Declarative users/ACLs/tokens rendered by secrets.nix once the
        # ntfy_auth_* keys exist in nix/per-host/core-pi.yaml; the server
        # runs deny-all from then on. null = today's open server.
        secretsFile =
          if config.sops.templates ? "ntfy.env" then config.sops.templates."ntfy.env".path else null;
      };

      ente = {
        enable = true;
        ip = "${myInventory.network.nodes.ente.ip}/24";
        inherit (myInventory.network.nodes.ente) domain;
        hostDataDir = "/var/lib/ente";
        minioRootPasswordFile = config.sops.secrets.ente_minio_root_password.path;
        jwtSecretFile = config.sops.secrets.ente_jwt_secret.path;
        keyEncryptionFile = config.sops.secrets.ente_key_encryption.path;
        keyHashFile = config.sops.secrets.ente_key_hash.path;
      };

      vaultwarden = {
        enable = true;
        ip = "${myInventory.network.nodes.vaultwarden.ip}/24";
        hostDataDir = "/var/lib/vaultwarden";
        inherit (myInventory.network.nodes.vaultwarden) domain port;
        # Argon2 PHC hash — add `vaultwarden_admin_token` to
        # kleinbem-secrets/nix/shared.yaml before the first deploy (needs
        # YubiKey). Until then /admin is disabled; the service still runs.
        adminTokenFile = config.sops.secrets.vaultwarden_admin_token.path;
      };

      gatus = {
        enable = true;
        ip = "${myInventory.network.nodes.gatus.ip}/24";
        inherit (myInventory.network.nodes.gatus) port;
        # Most probes use `[STATUS] < 500`: apps behind forward-auth or
        # Cloudflare Access answer a redirect, not 200. The list is a
        # bind-mounted file because container-factory builds the closure
        # centrally (ADR-002), so inline endpoints would never reach core-pi.
        endpointsFile = gatusEndpointsFile;
      };

      # Shared IdP: kleinbem.dev visitor login, persona OIDC, Matrix
      # federation, sigstore. Applications are managed by Terraform in
      # nix/infra/, not by NixOS options.
      authentik = {
        enable = true;
        ip = "${myInventory.network.nodes.authentik.ip}/24";
        hostDataDir = "/var/lib/authentik";
        inherit (myInventory.network.nodes.authentik) domain;
        secretKeyFile = config.sops.secrets.authentik_secret_key.path;
        postgresPasswordFile = config.sops.secrets.authentik_postgres_password.path;
        bootstrapAdminPasswordFile = config.sops.secrets.authentik_bootstrap_admin_password.path;
        bootstrapApiTokenFile = config.sops.secrets.authentik_bootstrap_api_token.path;
        # The preset's 1G gets the worker OOM-killed on every outpost refresh
        # once a forward_domain Proxy Provider exists, crash-looping the
        # container and the public login with it.
        memoryLimit = "2G";
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

  # Bind-mount the static site here: staticSites' own bindMounts never apply,
  # because nix-presets' caddy module merges a `lib.mkIf` with `//`, which keeps
  # only the mkIf content (its PKI-cert mounts are lost too). Fix it there,
  # then drop this. staticSites still generates the vhost.
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
