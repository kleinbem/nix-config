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
        name = "Vaultwarden";
        group = "Identity";
        url = "https://vault.kleinbem.dev";
        interval = "3m";
        conditions = [ "[STATUS] < 500" ];
      }
      {
        name = "Authentik";
        group = "Identity";
        url = "https://auth.kleinbem.dev";
        interval = "3m";
        conditions = [ "[STATUS] < 500" ];
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
    "${self}/modules/nixos/container-host.nix"
    "${self}/modules/nixos/services/container-updater.nix"
    "${self}/modules/nixos/rpi5-disko.nix"
    ./secrets.nix
    ./backup.nix
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
      # UPDATED 2026-09-22: added backend + filterForward — found while
      # doing the fleet-wide nftables migration that extraForwardRules
      # below (and container-host.nix's own broader bridge-accept
      # fragment) had been silently dead this whole time without these,
      # same class of bug hit on nixos-nvme/mac-mini/nasbook the same
      # night. This host is public-facing (Caddy fronts kleinbem.dev,
      # Vaultwarden, Authentik, etc.) so this genuinely activates
      # previously-unverified restriction logic — container-host.nix's own
      # broad "oifname cbr0 accept" fragment covers host->container traffic
      # (cloudflared -> Caddy) as a safety net regardless of this rule, but
      # verify all public services live after switching, same rigor as the
      # nixos-nvme migration earlier the same night.
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
    # ─── Clevis LUKS & Network Identity ─────────────────────────
    boot.clevis-initrd = {
      enable = true;
      luksDevice = luksVolumeName;
      hostIp = "10.0.0.22";
      secretFile = "${inputs.kleinbem-secrets}/initrd/cryptroot_core-pi.jwe";
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
        postgresPasswordFile = config.sops.secrets.ente_postgres_password.path;
        minioRootPasswordFile = config.sops.secrets.ente_minio_root_password.path;
        jwtSecretFile = config.sops.secrets.ente_jwt_secret.path;
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
        # `[STATUS] < 500` rather than `== 200`: several of these sit behind
        # Authentik forward-auth or Cloudflare Access (home, chat, n8n,
        # grafana), so an unauthenticated probe gets a redirect, not a
        # clean 200 — this only proves the edge + backend are up, not that
        # the app itself is healthy behind the login. status.kleinbem.dev
        # deliberately doesn't check itself.
        #
        # The actual list lives in gatusEndpointsFile above, not inline
        # here: container-factory builds this container's closure once,
        # centrally (ADR-002), so an inline `endpoints` list would only
        # ever reach container-factory's own build, never the container
        # core-pi actually runs. endpointsFile is bind-mounted into the
        # running container instead — see nix-presets' containers/gatus.nix.
        endpointsFile = gatusEndpointsFile;
      };

      # Shared IdP: replaces kleinbem-auth (decommissioned 2026-09-21 —
      # Phase 4 of the migration; kleinbem-site's own auth moved to this in
      # Phase 3) for kleinbem.dev visitor login,
      # and also serves persona OIDC / Matrix federation / sigstore — the
      # scope this preset was originally built for (see authentik.nix's own
      # description). One instance, multiple Applications configured inside
      # Authentik itself (not via NixOS options — that's Terraform's job,
      # see nix/infra/).
      authentik = {
        enable = true;
        ip = "${myInventory.network.nodes.authentik.ip}/24";
        hostDataDir = "/var/lib/authentik";
        inherit (myInventory.network.nodes.authentik) domain;
        secretKeyFile = config.sops.secrets.authentik_secret_key.path;
        postgresPasswordFile = config.sops.secrets.authentik_postgres_password.path;
        bootstrapAdminPasswordFile = config.sops.secrets.authentik_bootstrap_admin_password.path;
        bootstrapApiTokenFile = config.sops.secrets.authentik_bootstrap_api_token.path;
        # Preset default (1G, "comfortable for ~50 persona users") turned
        # out too tight once a forward_domain Proxy Provider existed:
        # confirmed live 2026-09-22 via `podman logs authentik-server` —
        # "Worker was sent SIGKILL! Perhaps out of memory?" — every single
        # time right after "refreshing outpost", crash-looping the whole
        # container (5-45s up, repeat) and taking kleinbem.dev's public
        # login down with it, since it's the same server process. Real hard
        # limit confirmed via `systemctl show container@authentik.service
        # -p MemoryMax` = 1073741824 (exactly 1G, not a fluke). core-pi has
        # room (7.9Gi total, ~4Gi available even mid-incident) — doubling
        # rather than micro-tuning since the actual per-provider-type cost
        # of an outpost refresh isn't characterized.
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
