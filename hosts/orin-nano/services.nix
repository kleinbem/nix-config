{
  config,
  lib,
  pkgs,
  myInventory,
  secretFile,
  ...
}:
{
  # ─── Virtualization ─────────────────────────────────────────
  containers = lib.mkIf config.my.containers.ollama.enable {
    ollama.config.nixpkgs.config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
      allowUnsupportedSystem = true;
    };
  };

  # RTSP creds for Frigate, gated on environmentFile so a camera-less Frigate
  # runs without the key. Create it before setting environmentFile.
  # Format: FRIGATE_RTSP_USER=… / FRIGATE_RTSP_PASSWORD=…
  sops.secrets.frigate_rtsp_env = lib.mkIf (config.my.containers.frigate.environmentFile != null) {
    sopsFile = secretFile "nix/per-host/orin-nano.yaml";
  };

  # ─── Frigate data disk (second SSD, nvme1n1) ────────────────
  # Stage-2 unlock for orin_frigate_crypt: with initrdUnlock = false disko
  # emits nothing to open it. Stage 2 because the keyfile is on /nix, inside
  # the Tang-unlocked root. nofail so a missing disk never wedges boot.
  environment.etc.crypttab.text = ''
    orin_frigate_crypt /dev/disk/by-partlabel/disk-second-frigate /nix/persist/etc/crypt/frigate.key luks,discard,nofail,x-systemd.requires=nix.mount,x-systemd.after=nix.mount
  '';

  # ─── AI Edge Services ──────────────────────────────────────
  my = {
    boot.clevis-initrd = {
      enable = true;
      luksDevice = "orin_crypt";
      hostIp = "10.0.0.15";
      # JWE lives in kleinbem-secrets (private): Tang-wrapped LUKS key material
      # must not sit in this public repo.
      secretFile = pkgs.writeText "cryptroot.jwe" (
        builtins.readFile (secretFile "initrd/cryptroot_orin-nano.jwe")
      );
      fallbackMessage = "Tang still unreachable; continuing (clevis falls back to passphrase)";
    };
    services = {
      tang.enable = true;
      # Nightly GPU half of the nix-packages mesh-llm canary; it serves on its
      # own ports (29337/23131/27842), so it coexists with the node below.
      meshLlmGpuRunner.enable = true;
      # The fleet's MeshLLM node that creates the mesh (always on, CUDA).
      # Qwen3-4B because goose needs tool calling.
      meshLlm = {
        enable = true;
        package = pkgs.mesh-llm-cuda;
        models = [ "Qwen3-4B-Q4_K_M" ];
      };

      container-updater = {
        enable = true;
        manifestUrl = "https://github.com/kleinbem/nix-config/releases/download/container-manifest/manifest.json";
        containers =
          let
            excludeFromUpdater = [ "llama-cpp" ];
            allEnabled = lib.attrNames (lib.filterAttrs (_: v: v.enable or false) config.my.containers);
          in
          lib.subtractLists excludeFromUpdater allEnabled;
      };
    };
    security.ai-hardening.enable = false; # Orin Nano runs no airlocked AI webapps; ai-airlock requires CONFIG_NFT_REDIR which JP6 lacks
    # Orin uses wired Ethernet, not wlo1 (Wi-Fi default)
    network.externalInterface = "enP8p1s0";

    containers = {
      ollama = {
        enable = false; # Switched to llama-cpp for better memory efficiency
        ip = "${myInventory.network.nodes.ollama-orin.ip}/24";
        hostDataDir = "/mnt/models/ollama";
        acceleration = "cuda";
        memoryLimit = "6G";
      };
      llama-cpp = {
        enable = false; # Replaced by my.services.meshLlm above
        enableCuda = true;
        ip = "10.85.46.126/24";
        modelPath = "/mnt/models/gemma-3-4b-it-Q4_K_M.gguf"; # Gemma 3 4B — fits 8GB unified mem with headroom
        contextSize = 8192; # KV cache is q4_0-quantized + flash-attn, so cheap even at 8k
        memoryLimit = "5G";
      };
      frigate = {
        # Camera-less, CPU-only smoke test. For GPU detection: enableGPU,
        # jetson, detector = "tensorrt" (engine built on-device), add cameras,
        # create frigate_rtsp_env and set environmentFile.
        enable = true;
        ip = "${myInventory.network.nodes.frigate.ip}/24";
        detector = "cpu"; # temp — bundled CPU model; target is "tensorrt"
        enableGPU = false; # temp — no GPU passthrough during the smoke test
        jetson = false; # temp — no Tegra /dev/nv* binds (target is true)
        # The preset default binds nodes this board (JetPack 6 / r36) lacks, and
        # a missing node fails container start. On r36 the iGPU lives under
        # /dev/nvgpu/igpu0/*. The minimal TensorRT set is still unconfirmed.
        jetsonDevices = [
          "/dev/nvhost-ctrl-gpu"
          "/dev/nvhost-gpu"
          "/dev/nvhost-as-gpu"
          "/dev/nvhost-prof-gpu"
          "/dev/nvmap"
          "/dev/nvgpu/igpu0/as"
          "/dev/nvgpu/igpu0/channel"
          "/dev/nvgpu/igpu0/ctrl"
          "/dev/nvgpu/igpu0/power"
          "/dev/nvgpu/igpu0/sched"
          "/dev/nvgpu/igpu0/tsg"
        ];
        mediaDir = "/mnt/data/frigate";
        hostDataDir = "/nix/persist/var/lib/frigate"; # persist across tmpfs reboots
        memoryLimit = "3G"; # leave room for mesh-llm (Qwen3-4B, ~3 GB) + syncthing + system on 8GB host
        # RTSP creds for Frigate's {VAR} substitution. null keeps the secret
        # optional; set "/run/secrets/frigate_rtsp_env" when adding cameras.
        environmentFile = null;
        innerConfig.services.frigate.settings = {
          # MQTT → Home Assistant. Off during the smoke test (hass-pi broker not
          # wired yet); the target values are kept here for when it goes on.
          mqtt = {
            host = "10.85.46.10"; # hass-pi
            enabled = false;
          };

          # No cameras yet; Frigate starts fine with an empty set. Target camera
          # (cameras VLAN; creds via {FRIGATE_RTSP_*}, never inline):
          #   cameras.front_door.ffmpeg.inputs = [{
          #     path = "rtsp://{FRIGATE_RTSP_USER}:{FRIGATE_RTSP_PASSWORD}@10.0.30.100:554/stream1";
          #     roles = [ "detect" "record" ];
          #   }];
          #   cameras.front_door.detect.enabled = true;
          #   cameras.front_door.record.enabled = true;
          cameras = { };

          # --- Detection settings ---
          objects.track = [
            "person"
            "car"
            "dog"
          ];

          # --- Birdseye (Combined View) ---
          birdseye = {
            enabled = true;
            mode = "continuous"; # Always show cameras in the grid
            width = 1280;
            height = 720;
          };

          # --- Global Recording & Retention ---
          record = {
            enabled = true;
            retain = {
              days = 7; # Keep 7 days of continuous recording (if enabled per camera)
              mode = "all";
            };
            events = {
              retain = {
                default = 14; # Keep 14 days of motion-detected events
                mode = "active_objects"; # Prioritize storing actual objects
              };
            };
          };

          # --- Snapshots (High Res Events) ---
          snapshots = {
            enabled = true;
            timestamp = true;
            bounding_box = true;
            retain.default = 14;
          };
        };
      };
      syncthing = {
        enable = true;
        ip = "${myInventory.network.nodes.syncthing-orin.ip}/24";
        hostDataDir = "/var/lib/images/syncthing";
        vaults = {
          # Container path = host path (persistent — / is tmpfs on Orin)
          "/home/martin/Develop/github.com/kleinbem/nix" = "/nix/persist/syncthing/nix-config";
        };
      };
    };
    monitoring.node.enable = true;
  };

  # Create persistent syncthing vault and frigate data directories on ext4 /nix
  systemd.tmpfiles.rules = [
    "d /nix/persist/syncthing/nix-config 0755 1000 100 - -"
    "d /nix/persist/var/lib/frigate 0755 root root - -"
  ];
}
