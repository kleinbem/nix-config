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
  # Assign each container a unique address in the factory subnet purely to keep
  # evaluation clean; uniqueness is irrelevant to the built closure.
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
      ip = ip 23;
      hostDataDir = dataDir "open-webui";
    };
    qdrant = {
      ip = ip 24;
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
      ip = ip 30;
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
      ip = ip 33;
      hostDataDir = dataDir "openclaw";
    };
    monitoring = {
      ip = ip 34;
      hostDataDir = dataDir "monitoring";
    };
    agent-zero = {
      ip = ip 35;
      hostDataDir = dataDir "agent-zero";
    };
    anythingllm = {
      ip = ip 36;
      hostDataDir = dataDir "anythingllm";
    };
    caddy.ip = ip 37;
    cups.ip = ip 38;
    frigate.ip = ip 39;
    home-assistant.ip = ip 40;
    paperless.ip = ip 41;
    authelia.hostDataDir = dataDir "authelia";
    github-runner = {
      ip = ip 42;
      hostDataDir = dataDir "github-runner";
      secretsFile = "/run/secrets/factory-dummy"; # host-level bind mount; not in closure
    };
    llama-cpp = {
      ip = ip 43;
      modelPath = "/var/lib/factory/llama/model.gguf"; # host-level; not in closure
    };
    dashboard = {
      ip = ip 44;
      hostBridgeIp = "10.85.46.1";
    };
    agent-team = { };
    netdata = { };
    syncthing = { };
    backup = { };
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
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.agent-team
    inputs.nix-presets.nixosModules.cups
    inputs.nix-presets.nixosModules.github-runner
    inputs.nix-presets.nixosModules.ollama
    inputs.nix-presets.nixosModules.syncthing
    inputs.nix-presets.nixosModules.backup
    inputs.nix-presets.nixosModules.paperless
    inputs.nix-presets.nixosModules.llama-cpp
    inputs.nix-presets.nixosModules.frigate
    inputs.nix-presets.nixosModules.home-assistant
    inputs.nix-presets.nixosModules.anythingllm
    inputs.nix-presets.nixosModules.dashboard
    # NOTE: dashboard-homer / dashboard-homepage are alternate frontends that
    # re-declare the same `my.containers.dashboard` option slot, so they cannot
    # coexist with `dashboard` in one host. Their closures are near-identical
    # (nginx + static assets) and already covered by caching `dashboard`. To
    # cache a specific skin, swap the import above for that variant.
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

    containers = lib.mapAttrs (name: def: def // { enable = wanted name; }) catalogue;
  };
}
