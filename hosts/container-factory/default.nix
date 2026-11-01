{
  lib,
  inputs,
  myInventory,
  deployedContainers ? null,
  ...
}:
# Build/cache factory for all standalone containers (ADR 002). It never boots:
# CI builds `config.containers.<name>.path` from here, pushes to Attic and
# publishes the manifest devices pull from.
# `deployedContainers` (from modules/flake/hosts.nix) limits the build to what
# some host deploys; null enables the whole catalogue.
# Data dirs and secret paths don't reach the inner closure, so dummies do.
let
  # Dummy address, only for containers that run on nixos-nvme (.46). The baked
  # default gateway is .1 of the container's /24, so anything deployed to
  # another subnet must use its real inventory.nix address.
  ip = n: "10.85.46.${toString n}/24";
  dataDir = name: "/var/lib/factory/${name}";

  # Full catalogue: every nspawn container preset and the host-level attrs its
  # closure eval needs. Keyed by `my.containers.<name>` option name (a single
  # option may emit extra containers, e.g. langfuse → langfuse + langfuse-db;
  # deployment checks match on the option name, which hosts also enable).
  catalogue = {
    n8n = {
      ip = ip 20;
      hostDataDir = dataDir "n8n";
    };
    attic = {
      ip = "${myInventory.network.nodes.attic.ip}/24"; # core-pi
      hostDataDir = dataDir "attic";
      secretsFile = "/run/secrets/factory-dummy";
      # Baked into the closure (the container applies it to the cache on
      # start), so it is set here, not on core-pi.
      inherit (import ../../modules/nixos/keys.nix) upstreamCacheKeyNames;
    };
    code-server = {
      ip = ip 22;
      hostDataDir = dataDir "code-server";
    };
    open-webui = {
      ip = "${myInventory.network.nodes.open-webui.ip}/24"; # mac-mini
      hostDataDir = dataDir "open-webui";
      secretsFile = "/run/secrets/factory-dummy";
      openaiUrl = "http://${myInventory.hosts.orin-nano.ip}:11434/v1";
      oidc.enable = true;
    };
    qdrant = {
      ip = "${myInventory.network.nodes.qdrant.ip}/24"; # nasbook
      hostDataDir = dataDir "qdrant";
    };
    playground = {
      ip = ip 25;
      hostDataDir = dataDir "playground";
    };
    langfuse = {
      # Real address, not a dummy: langfuse-db's pg_hba admits only the
      # app container's IP, so it's baked into that closure.
      ip = "${myInventory.network.nodes.langfuse.ip}/24"; # nixos-nvme
      hostDataDir = dataDir "langfuse";
      # Non-null so the cached closure includes the password-setup branch
      # (same dummy-path convention as ente/authentik below).
      dbPasswordFile = "/run/secrets/factory-dummy";
    };
    litellm = {
      ip = ip 29;
      hostDataDir = dataDir "litellm";
    };
    loki = {
      ip = "${myInventory.network.nodes.loki.ip}/24"; # nasbook
      hostDataDir = dataDir "loki";
    };
    crowdsec = {
      ip = "${myInventory.network.nodes.crowdsec.ip}/24"; # core-pi
      hostDataDir = dataDir "crowdsec";
    };
    ollama = {
      ip = ip 32;
      hostDataDir = dataDir "ollama";
    };
    openclaw = {
      ip = "${myInventory.network.nodes.openclaw.ip}/24"; # hass-pi
      hostDataDir = dataDir "openclaw";
    };
    music-assistant = {
      ip = "${myInventory.network.nodes.music-assistant.ip}/24"; # hass-pi
      hostDataDir = dataDir "music-assistant";
    };
    monitoring = {
      ip = "${myInventory.network.nodes.monitoring.ip}/24"; # mac-mini
      hostDataDir = dataDir "monitoring";
      # Non-null so the cached closure includes the auth.generic_oauth block.
      grafanaOidc = {
        enable = true;
        clientSecretFile = "/run/secrets/factory-dummy";
      };
    };
    agent-zero = {
      ip = "${myInventory.network.nodes.agent-zero.ip}/24"; # mac-mini
      hostDataDir = dataDir "agent-zero";
    };
    anythingllm = {
      ip = "${myInventory.network.nodes.anythingllm.ip}/24"; # mac-mini
      hostDataDir = dataDir "anythingllm";
    };
    buzz = {
      ip = ip 48;
      hostDataDir = dataDir "buzz";
      secretsFile = "/run/secrets/factory-dummy";
      typesenseApiKeyFile = "/run/secrets/factory-dummy";
      relayUrl = "wss://buzz.example.invalid";
    };
    # persona-runtime (an attrsOf preset) isn't here: it stays embedded on mac-mini.
    hermes = {
      ip = "${myInventory.network.nodes.hermes.ip}/24"; # mac-mini
      hostDataDir = dataDir "hermes";
      secretsFile = "/run/secrets/factory-dummy";
    };
    caddy = {
      ip = "${myInventory.network.nodes.caddy.ip}/24"; # core-pi
      hostIP = myInventory.network.nodes.caddy.ip;
      proxyTargets = lib.filterAttrs (_: v: v ? externalPort) myInventory.network.nodes;
      globalMaintenance = myInventory.globalMaintenance or false;
      staticSites."kleinbem.dev" = {
        hostPath = "/var/www/kleinbem.dev";
      };
    };
    cups.ip = "${myInventory.network.nodes.cups.ip}/24"; # core-pi
    frigate.ip = ip 39;
    home-assistant.ip = "${myInventory.network.nodes.home-assistant.ip}/24"; # hass-pi
    paperless.ip = "${myInventory.network.nodes.paperless.ip}/24"; # nasbook
    stalwart = {
      ip = "${myInventory.network.nodes.stalwart.ip}/24"; # mac-mini
      hostDataDir = dataDir "stalwart";
      # Non-null so the closure includes the fallback-admin block.
      adminPasswordFile = "/run/secrets/factory-dummy";
    };
    forgejo = {
      ip = "${myInventory.network.nodes.forgejo.ip}/24"; # mac-mini, real address like stalwart
      hostDataDir = dataDir "forgejo";
      # Must match mac-mini: the admin and OIDC settings change the
      # bootstrap unit, so they change the closure. Paths are bind mounts
      # supplied by the deploying host.
      admin.passwordFile = "/run/secrets/factory-dummy";
      oidc = {
        enable = true;
        clientSecretFile = "/run/secrets/factory-dummy";
      };
    };
    # github-runner: opt-in debug runner, built embedded on nixos-nvme
    # (excludeFromUpdater) so it's not a factory target.
    llama-cpp = {
      ip = ip 43;
      modelPath = "/var/lib/factory/llama/model.gguf"; # host-level; not in closure
    };
    dashboard = {
      ip = "${myInventory.network.nodes.dashboard.ip}/24"; # core-pi
      hostBridgeIp = "10.85.48.1";
    };
    ente = {
      ip = "${myInventory.network.nodes.ente.ip}/24"; # core-pi
      # Real hostname, not a dummy: it's baked into museum's WebAuthn config.
      inherit (myInventory.network.nodes.ente) domain;
      hostDataDir = dataDir "ente";
      # Non-null so the env-setup script keeps every `cat` branch; a null
      # bakes that branch out of the cached closure.
      minioRootPasswordFile = "/run/secrets/factory-dummy";
      jwtSecretFile = "/run/secrets/factory-dummy";
      keyEncryptionFile = "/run/secrets/factory-dummy";
      keyHashFile = "/run/secrets/factory-dummy";
    };
    vaultwarden = {
      ip = "${myInventory.network.nodes.vaultwarden.ip}/24"; # core-pi
      hostDataDir = dataDir "vaultwarden";
      # Non-null so the cached closure includes the env-setup + admin branch.
      # Real bind mount is supplied by the deploying host (sops path).
      adminTokenFile = "/run/secrets/factory-dummy";
    };
    gatus = {
      ip = "${myInventory.network.nodes.gatus.ip}/24"; # core-pi
      # Non-null so the cached closure includes the config-setup branch.
      endpointsFile = "/run/secrets/factory-dummy";
    };
    authentik = {
      ip = "${myInventory.network.nodes.authentik.ip}/24"; # core-pi
      hostDataDir = dataDir "authentik";
      # All non-null so the cached closure's env-setup writes every line
      # (each reads a fixed in-container path — see authentik.nix — bind-
      # mounted onto those paths by the deploying host, core-pi).
      secretKeyFile = "/run/secrets/factory-dummy";
      postgresPasswordFile = "/run/secrets/factory-dummy";
      bootstrapAdminPasswordFile = "/run/secrets/factory-dummy";
      bootstrapApiTokenFile = "/run/secrets/factory-dummy";
    };
    ntfy.ip = "${myInventory.network.nodes.ntfy.ip}/24"; # core-pi
    agent-team.ip = "${myInventory.network.nodes.agent-team.ip}/24"; # nasbook
    netdata = { };
    syncthing.ip = "${myInventory.network.nodes.syncthing.ip}/24"; # nasbook
    backup.ip = "${myInventory.network.nodes.backup.ip}/24"; # nasbook
    dev-db = {
      ip = "${myInventory.network.nodes.dev-db.ip}/24"; # nixos-nvme
      hostDataDir = dataDir "dev-db";
    };
    caido = {
      ip = "${myInventory.network.nodes.caido.ip}/24"; # nixos-nvme
      hostDataDir = dataDir "caido";
    };
    garage-ui = {
      ip = "${myInventory.network.nodes.garage-ui.ip}/24"; # nixos-nvme
      hostDataDir = dataDir "garage-ui";
      secretsFile = "/run/secrets/factory-dummy";
      # Baked into the closure: the OIDC login block only exists when set here.
      oidc.enable = true;
    };
    qbittorrent = {
      ip = "${myInventory.network.nodes.qbittorrent.ip}/24"; # nasbook
      hostDataDir = dataDir "qbittorrent";
      downloadsDir = "/var/lib/factory/downloads";
    };
    miniflux = {
      ip = "${myInventory.network.nodes.miniflux.ip}/24"; # nasbook
      hostDataDir = dataDir "miniflux";
    };
    # Hybrid containers (comfyui, langflow) run Podman inside nspawn containers
    # with runtime image pulling and produce no static factory closure to cache.
  };

  # Hosts register real container names, the catalogue uses option names.
  # List the real names here where a preset's container name differs.
  realContainerNames = {
    dashboard = [ "dashboard-homepage" ];
  };
  wanted =
    name:
    deployedContainers == null
    || builtins.elem name deployedContainers
    || lib.any (n: builtins.elem n deployedContainers) (realContainerNames.${name} or [ ]);
in
{
  imports = [
    ../../modules/nixos/options.nix

    # --- Every container module exposed by nix-presets ---
    inputs.nix-presets.nixosModules.n8n
    inputs.nix-presets.nixosModules.attic
    inputs.nix-presets.nixosModules.code-server
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.qdrant
    inputs.nix-presets.nixosModules.ntfy
    inputs.nix-presets.nixosModules.stalwart
    inputs.nix-presets.nixosModules.forgejo
    inputs.nix-presets.nixosModules.playground
    inputs.nix-presets.nixosModules.caddy
    inputs.nix-presets.nixosModules.comfyui
    inputs.nix-presets.nixosModules.langfuse
    inputs.nix-presets.nixosModules.langflow
    inputs.nix-presets.nixosModules.monitoring
    inputs.nix-presets.nixosModules.litellm
    inputs.nix-presets.nixosModules.loki
    inputs.nix-presets.nixosModules.crowdsec
    inputs.nix-presets.nixosModules.netdata
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.buzz
    inputs.nix-presets.nixosModules.hermes
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.agent-team
    inputs.nix-presets.nixosModules.cups
    inputs.nix-presets.nixosModules.ollama
    inputs.nix-presets.nixosModules.syncthing
    inputs.nix-presets.nixosModules.backup
    inputs.nix-presets.nixosModules.paperless
    inputs.nix-presets.nixosModules.llama-cpp
    inputs.nix-presets.nixosModules.frigate
    inputs.nix-presets.nixosModules.home-assistant
    inputs.nix-presets.nixosModules.music-assistant
    inputs.nix-presets.nixosModules.anythingllm
    inputs.nix-presets.nixosModules.dashboard-homepage
    inputs.nix-presets.nixosModules.ente
    inputs.nix-presets.nixosModules.vaultwarden
    inputs.nix-presets.nixosModules.authentik
    inputs.nix-presets.nixosModules.gatus
    inputs.nix-presets.nixosModules.dev-db
    inputs.nix-presets.nixosModules.caido
    inputs.nix-presets.nixosModules.garage-ui
    inputs.nix-presets.nixosModules.qbittorrent
    inputs.nix-presets.nixosModules.miniflux
    # dashboard-homer declares the same `my.containers.dashboard` option as
    # dashboard-homepage, so only one can be imported. Swap them to cache homer.
  ];

  # The same held packages as the hosts (modules/nixos/base.nix).
  nixpkgs.overlays = [
    inputs.nix-packages.overlays.default
    (inputs.nix-detour-fleet.lib.mkOverlay {
      extraOverlays = [ inputs.nix-packages.overlays.default ];
    })
  ];

  # Minimal host scaffolding to satisfy NixOS assertions during evaluation.
  fileSystems."/" = {
    device = "dummy";
    fsType = "tmpfs";
  };
  boot.loader.systemd-boot.enable = true;
  system.stateVersion = "25.11";

  my = {
    network = {
      hostAddress = "10.85.46.1";
      bridge = "br0";
    };
    hardware.gpuRenderNode = "/dev/dri/renderD128";
    # Build-only host that enables every preset → every preset registers
    # its backup items here. Backups belong to the hosts that actually run
    # the services, not to this one.
    backup.warnIfDisabled = false;

    containers = lib.mapAttrs (name: def: def // { enable = wanted name; }) catalogue;
  };
}
