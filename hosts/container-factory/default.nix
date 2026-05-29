{ inputs, ... }:
# ---------------------------------------------------------------------------
# Dedicated build/cache factory for ALL decoupled containers.
#
# This host does not boot. Its sole purpose is to expose every container's
# system closure at `config.containers.<name>.path` so CI can build & push
# them to the Attic cache (see .github/workflows/build-containers.yaml).
#
# Every container is force-enabled with `standaloneRunner = false` so `.path`
# resolves to a real, buildable closure rather than the runtime symlink string
# (`/var/lib/machines/<name>/current`). IPs / data dirs / secret paths are
# host-level container attributes and do NOT affect the inner closure, so
# dummy-but-valid values are sufficient for building & caching.
# ---------------------------------------------------------------------------
let
  # Assign each container a unique address in the factory subnet purely to keep
  # evaluation clean; uniqueness is irrelevant to the built closure.
  ip = n: "10.85.46.${toString n}/24";
  dataDir = name: "/var/lib/factory/${name}";
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

    containers = {
      # ---- Standard containers (ip + hostDataDir required) ----
      n8n = {
        enable = true;
        ip = ip 20;
        hostDataDir = dataDir "n8n";
      };
      attic = {
        enable = true;
        ip = ip 21;
        hostDataDir = dataDir "attic";
      };
      code-server = {
        enable = true;
        ip = ip 22;
        hostDataDir = dataDir "code-server";
      };
      open-webui = {
        enable = true;
        ip = ip 23;
        hostDataDir = dataDir "open-webui";
      };
      qdrant = {
        enable = true;
        ip = ip 24;
        hostDataDir = dataDir "qdrant";
      };
      playground = {
        enable = true;
        ip = ip 25;
        hostDataDir = dataDir "playground";
      };
      langfuse = {
        enable = true;
        ip = ip 27;
        hostDataDir = dataDir "langfuse";
      };
      litellm = {
        enable = true;
        ip = ip 29;
        hostDataDir = dataDir "litellm";
      };
      loki = {
        enable = true;
        ip = ip 30;
        hostDataDir = dataDir "loki";
      };
      crowdsec = {
        enable = true;
        ip = ip 31;
        hostDataDir = dataDir "crowdsec";
      };
      ollama = {
        enable = true;
        ip = ip 32;
        hostDataDir = dataDir "ollama";
      };
      openclaw = {
        enable = true;
        ip = ip 33;
        hostDataDir = dataDir "openclaw";
      };
      monitoring = {
        enable = true;
        ip = ip 34;
        hostDataDir = dataDir "monitoring";
      };
      agent-zero = {
        enable = true;
        ip = ip 35;
        hostDataDir = dataDir "agent-zero";
      };
      anythingllm = {
        enable = true;
        ip = ip 36;
        hostDataDir = dataDir "anythingllm";
      };

      # ---- Only ip required ----
      caddy.enable = true;
      caddy.ip = ip 37;
      cups.enable = true;
      cups.ip = ip 38;
      frigate.enable = true;
      frigate.ip = ip 39;
      home-assistant.enable = true;
      home-assistant.ip = ip 40;
      paperless.enable = true;
      paperless.ip = ip 41;

      # ---- Only hostDataDir required (ip has a module default) ----
      authelia = {
        enable = true;
        hostDataDir = dataDir "authelia";
      };

      # ---- Extra required options ----
      github-runner = {
        enable = true;
        ip = ip 42;
        hostDataDir = dataDir "github-runner";
        secretsFile = "/run/secrets/factory-dummy"; # host-level bind mount; not in closure
      };
      llama-cpp = {
        enable = true;
        ip = ip 43;
        modelPath = "/var/lib/factory/llama/model.gguf"; # host-level; not in closure
      };
      dashboard = {
        enable = true;
        ip = ip 44;
        hostBridgeIp = "10.85.46.1";
      };

      # ---- Fully defaulted (just enable) ----
      agent-team.enable = true;
      netdata.enable = true;
      syncthing.enable = true;
      backup.enable = true;

      # ---- OCI/podman containers (NOT Nix closures) ----
      # comfyui, vllm, langflow run via virtualisation.oci-containers and pull
      # upstream images at runtime, so they produce no `config.containers.<name>`
      # entry and nothing for Attic to cache. Enabled here only to keep this a
      # complete "all containers" declaration; they won't appear in the CI matrix.
      comfyui = {
        enable = true;
        ip = ip 26;
        hostDataDir = dataDir "comfyui";
      };
      langflow = {
        enable = true;
        ip = ip 28;
        hostDataDir = dataDir "langflow";
      };
      vllm.enable = true;
    };
  };
}
