{
  lib,
  inputs,
  deployedContainers ? null,
  ...
}:
# ---------------------------------------------------------------------------
# Dedicated build/cache factory for ALL decoupled containers (ADR 002).
#
# This host does not boot. Its sole purpose is to expose container system
# closures at `config.containers.<name>.path` so CI can build & push them to
# Attic and publish the container manifest devices consume (see
# .github/workflows/build-all.yaml + promote-production.yaml).
#
# DEPLOYMENT-DRIVEN: `deployedContainers` (a specialArg computed in
# modules/flake/hosts.nix from every real host's container-updater
# registrations, plus an explicit pre-warm extras list) decides which
# catalogue entries are enabled. The factory builds exactly what some device
# will request from the manifest — nothing more. Passing null (e.g. a manual
# `nix build` without the specialArg wiring) enables the full catalogue.
#
# Containers are force-built with `standaloneRunner = false` so `.path`
# resolves to a real, buildable closure rather than the runtime symlink
# string (`/var/lib/machines/<name>/current`). IPs / data dirs / secret paths
# are host-level container attributes and do NOT affect the inner closure, so
# dummy-but-valid values are sufficient for building & caching.
# ---------------------------------------------------------------------------
let
  # Dummy .46 address for containers that ONLY ever deploy to nixos-nvme
  # (the .46 subnet). mkContainer now derives the container's baked default
  # gateway from `.1` of this address's /24, so any container that deploys
  # to another host's subnet MUST pass its real address here (see the .47/
  # .48/.49/.50 entries below) — a dummy .46 would bake a 10.85.46.1 gateway
  # that doesn't exist on that host. Source of truth: inventory.nix.
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
      ip = ip 21;
      hostDataDir = dataDir "attic";
      secretsFile = "/run/secrets/factory-dummy";
    };
    code-server = {
      ip = ip 22;
      hostDataDir = dataDir "code-server";
    };
    open-webui = {
      ip = "10.85.50.3/24"; # mac-mini
      hostDataDir = dataDir "open-webui";
    };
    qdrant = {
      ip = "10.85.47.105/24"; # nasbook
      hostDataDir = dataDir "qdrant";
    };
    playground = {
      ip = ip 25;
      hostDataDir = dataDir "playground";
    };
    langfuse = {
      ip = ip 27;
      hostDataDir = dataDir "langfuse";
    };
    litellm = {
      ip = ip 29;
      hostDataDir = dataDir "litellm";
    };
    loki = {
      ip = "10.85.47.116/24"; # nasbook
      hostDataDir = dataDir "loki";
    };
    crowdsec = {
      ip = ip 31;
      hostDataDir = dataDir "crowdsec";
    };
    ollama = {
      ip = ip 32;
      hostDataDir = dataDir "ollama";
    };
    openclaw = {
      ip = "10.85.49.112/24"; # hass-pi
      hostDataDir = dataDir "openclaw";
    };
    monitoring = {
      ip = "10.85.50.2/24"; # mac-mini
      hostDataDir = dataDir "monitoring";
    };
    agent-zero = {
      ip = ip 35;
      hostDataDir = dataDir "agent-zero";
    };
    anythingllm = {
      ip = "10.85.50.6/24"; # mac-mini
      hostDataDir = dataDir "anythingllm";
    };
    # hermes deliberately absent (2026-08-07): it became attrsOf (one
    # instance per persona) when the persona-fleet needed its own workers.
    # Reproducibly triggers "infinite recursion encountered" when evaluated
    # here specifically — confirmed with even a maximally minimal attrsOf
    # schema (bare enable/ip/hostDataDir), so it's a structural conflict
    # between attrsOf-of-submodule + the shared mkContainer factory (likely
    # its `config.my.containers.standaloneRunner or false` sibling-option
    # read in nix-presets/lib/factory.nix) and this host's specific
    # catalogue+deployedContainers construction — not something narrowed
    # down further without real effort. Every other preset here is still a
    # singular submodule and unaffected. Net effect: hermes containers
    # aren't CI-pre-cached via the factory; they still build fine directly
    # on the deploying host (mac-mini). Revisit if/when another preset needs
    # to go attrsOf too.
    buzz = {
      ip = ip 48;
      hostDataDir = dataDir "buzz";
      secretsFile = "/run/secrets/factory-dummy";
      typesenseApiKeyFile = "/run/secrets/factory-dummy";
      relayUrl = "wss://buzz.example.invalid";
    };
    caddy.ip = ip 37;
    # cups: inventory node still has a .46 IP but it deploys on core-pi (.48)
    # — pre-existing inventory inconsistency, tracked separately. Leaving the
    # dummy; cups's gateway is wrong either way until that's fixed.
    cups.ip = ip 38;
    frigate.ip = ip 39;
    home-assistant.ip = "10.85.49.10/24"; # hass-pi
    paperless.ip = "10.85.47.131/24"; # nasbook
    stalwart = {
      # REAL deployment IP, not a dummy — mkContainer now derives the
      # container's baked default gateway from its own address (.1 of the
      # /24), so a standalone closure must be built with the address it
      # will actually run on. Stalwart runs on mac-mini (10.85.50.0/24);
      # a .46 dummy would bake a 10.85.46.1 gateway that doesn't exist
      # there. Source of truth: inventory.nix network.nodes.stalwart.
      ip = "10.85.50.8/24";
      hostDataDir = dataDir "stalwart";
      # Non-null so the closure includes the fallback-admin block (its
      # secret path is a fixed /run/credentials/... macro, not this
      # value). Real bind mount is supplied by the deploying host.
      adminPasswordFile = "/run/secrets/factory-dummy";
    };
    authelia = {
      hostDataDir = dataDir "authelia";
      # Host-level bind mounts; not in closure. The factory has no sops-nix,
      # so the preset's `config.sops.secrets.*` defaults would fail to eval.
      jwtSecretFile = "/run/secrets/factory-dummy";
      sessionSecretFile = "/run/secrets/factory-dummy";
      storageEncryptionKeyFile = "/run/secrets/factory-dummy";
    };
    # github-runner: opt-in debug runner, built embedded on nixos-nvme
    # (excludeFromUpdater) so it's not a factory target.
    llama-cpp = {
      ip = ip 43;
      modelPath = "/var/lib/factory/llama/model.gguf"; # host-level; not in closure
    };
    dashboard = {
      ip = "10.85.48.103/24"; # core-pi
      hostBridgeIp = "10.85.48.1";
    };
    ente = {
      ip = "10.85.48.133/24"; # core-pi
      hostDataDir = dataDir "ente";
    };
    vaultwarden = {
      ip = "10.85.48.135/24"; # core-pi
      hostDataDir = dataDir "vaultwarden";
      # Non-null so the cached closure includes the env-setup + admin branch.
      # Real bind mount is supplied by the deploying host (sops path).
      adminTokenFile = "/run/secrets/factory-dummy";
    };
    kleinbem-auth = {
      ip = "10.85.48.140/24"; # core-pi
      hostDataDir = dataDir "kleinbem-auth";
      # All non-null so the cached closure's env-setup writes every secret
      # line (each reads a fixed in-container path; the real sops files are
      # bind-mounted onto those paths by the deploying host, core-pi). The
      # OAuth ones matter now-vs-later: with them present the closure is
      # already complete, so wiring Google/Facebook is a sops edit + redeploy
      # with no container rebuild.
      betterAuthSecretFile = "/run/secrets/factory-dummy";
      googleClientIdFile = "/run/secrets/factory-dummy";
      googleClientSecretFile = "/run/secrets/factory-dummy";
      facebookClientIdFile = "/run/secrets/factory-dummy";
      facebookClientSecretFile = "/run/secrets/factory-dummy";
    };
    ntfy.ip = "10.85.48.131/24"; # core-pi
    agent-team.ip = "10.85.47.118/24"; # nasbook
    netdata = { };
    syncthing.ip = "10.85.47.127/24"; # nasbook
    backup.ip = "10.85.47.128/24"; # nasbook
    # OCI/podman containers (comfyui, vllm, langflow) are deliberately absent:
    # they run via virtualisation.oci-containers, pull upstream images at
    # runtime, and produce no `config.containers.<name>` closure to cache.
  };

  wanted = name: deployedContainers == null || builtins.elem name deployedContainers;
in
{
  imports = [
    ../../modules/nixos/options.nix

    # --- Every container module exposed by nix-presets ---
    # (dashboard / dashboard-homer / dashboard-homepage share the same
    #  `my.containers.dashboard` options but emit distinct container names,
    #  so importing all three yields three buildable containers.)
    inputs.nix-presets.nixosModules.n8n
    inputs.nix-presets.nixosModules.attic
    inputs.nix-presets.nixosModules.code-server
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.qdrant
    inputs.nix-presets.nixosModules.ntfy
    inputs.nix-presets.nixosModules.stalwart
    inputs.nix-presets.nixosModules.playground
    inputs.nix-presets.nixosModules.caddy
    inputs.nix-presets.nixosModules.comfyui
    inputs.nix-presets.nixosModules.langfuse
    inputs.nix-presets.nixosModules.langflow
    inputs.nix-presets.nixosModules.vllm
    inputs.nix-presets.nixosModules.monitoring
    inputs.nix-presets.nixosModules.litellm
    inputs.nix-presets.nixosModules.loki
    inputs.nix-presets.nixosModules.crowdsec
    inputs.nix-presets.nixosModules.netdata
    inputs.nix-presets.nixosModules.authelia
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.buzz
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
    inputs.nix-presets.nixosModules.anythingllm
    inputs.nix-presets.nixosModules.dashboard
    inputs.nix-presets.nixosModules.ente
    inputs.nix-presets.nixosModules.vaultwarden
    inputs.nix-presets.nixosModules.kleinbem-auth
    # NOTE: dashboard-homer / dashboard-homepage are alternate frontends that
    # re-declare the same `my.containers.dashboard` option slot, so they cannot
    # coexist with `dashboard` in one host. Their closures are near-identical
    # (nginx + static assets) and already covered by caching `dashboard`. To
    # cache a specific skin, swap the import above for that variant.
  ];

  # This host doesn't import base.nix, but container presets that run a
  # nix-packages-built service in their innerConfig (kleinbem-auth) need
  # pkgs.<name> to resolve during the factory's closure eval.
  nixpkgs.overlays = [ inputs.nix-packages.overlays.default ];

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

    containers = lib.mapAttrs (name: def: def // { enable = wanted name; }) catalogue;
  };
}
