{
  config,
  lib,
  pkgs,
  inputs,
  myInventory,
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

  # RTSP creds for Frigate — decrypted only when Frigate is enabled, so this
  # disabled scaffold never requires frigate_rtsp_env to exist in secrets.yaml
  # yet (create it before flipping enable = true; see the container preset's
  # environmentFile option). Format: FRIGATE_RTSP_USER=… / FRIGATE_RTSP_PASSWORD=…
  sops.secrets.frigate_rtsp_env = lib.mkIf config.my.containers.frigate.enable { };

  # ─── AI Edge Services ──────────────────────────────────────
  my = {
    boot.clevis-initrd = {
      enable = true;
      luksDevice = "orin_crypt";
      hostIp = "10.0.0.15";
      # JWE lives in nix-secrets (private): Tang-wrapped LUKS key material
      # must not sit in this public repo.
      secretFile = pkgs.writeText "cryptroot.jwe" (
        builtins.readFile "${inputs.nix-secrets}/initrd/cryptroot_orin-nano.jwe"
      );
      fallbackMessage = "Tang still unreachable; continuing (clevis falls back to passphrase)";
    };
    services.tang.enable = true;
    security.ai-hardening.enable = true; # AI workloads benefit from the strict-egress airlock
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
        enable = true; # Serving Gemma via llama.cpp (CUDA)
        ip = "10.85.46.126/24";
        modelPath = "/mnt/models/gemma-3-4b-it-Q4_K_M.gguf"; # Gemma 3 4B — fits 8GB unified mem with headroom
        contextSize = 8192; # KV cache is q4_0-quantized + flash-attn, so cheap even at 8k
        memoryLimit = "5G";
      };
      frigate = {
        # Phase-1 scaffold (GPU TensorRT detection + CPU decode). Keep OFF
        # until the SSD is provisioned AND the Tegra device list + on-device
        # TensorRT engine are validated on the real Orin (see frigate.nix).
        enable = false;
        ip = "${myInventory.network.nodes.frigate.ip}/24";
        detector = "tensorrt";
        jetson = true; # Tegra device passthrough; no desktop DRI node / VAAPI
        # Validated on the real Orin 2026-07-23 (JetPack 6 / r36). The preset's
        # default list has 4 nodes THIS board does not expose (nvhost-ctrl,
        # -nvdec, -vic, -nvjpg) — binding a missing node fails container start —
        # and on r36 the iGPU/CUDA lives under /dev/nvgpu/igpu0/*, not the legacy
        # nvhost-*-gpu nodes alone. This is the present GPU-compute set; the exact
        # minimal set for TensorRT gets confirmed on the first test-enable.
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
        memoryLimit = "3G"; # leave room for llama-cpp + syncthing + system on 8GB host
        # Camera RTSP creds: sops secret → env-file → Frigate {VAR} substitution.
        # Literal path (= sops default /run/secrets/<name>) rather than
        # config.sops.secrets.….path, so nothing references the secret while
        # Frigate is OFF — the secret itself is declared below, gated on enable.
        environmentFile = "/run/secrets/frigate_rtsp_env";
        innerConfig.services.frigate.settings = {
          # --- MQTT is required for Home Assistant integration ---
          mqtt = {
            host = "10.85.46.10"; # Pointing to hass-pi for now, assuming MQTT is there or integrated
            enabled = true;
          };

          # --- Sample Camera Configuration ---
          # Cameras live in the cameras VLAN (10.0.30.0/24, NO WAN — see the
          # openwrt NETWORK_PLAN). orin is in infra, which the firewall matrix
          # lets reach cameras, so Frigate can pull the stream. Credentials use
          # Frigate's {FRIGATE_RTSP_*} env substitution — the real values come
          # from a sops secret injected into the container env (nix-secrets),
          # NEVER inline here. Pin the camera to 10.0.30.100 via a DHCP
          # reservation (MAC) in openwrt-secrets ansible-vars.yaml.
          cameras = {
            front_door = {
              ffmpeg.inputs = [
                {
                  path = "rtsp://{FRIGATE_RTSP_USER}:{FRIGATE_RTSP_PASSWORD}@10.0.30.100:554/stream1";
                  roles = [
                    "detect"
                    "record"
                  ];
                }
              ];
              detect.enabled = true;
              record.enabled = true;
              # Phase 1: CPU decode (no hwaccel_args). Do NOT use preset-nvidia-*
              # (discrete-GPU/nvcodec path) on Tegra. Phase 2 will add a
              # jetson decode preset once an L4T (nvmpi) ffmpeg is packaged.
            };
          };

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
