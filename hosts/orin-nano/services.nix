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

  # RTSP creds for Frigate — only required once a camera env-file is actually
  # wired (containers.frigate.environmentFile != null). Gating on `.enable` alone
  # meant a camera-less bring-up still demanded this key exist; gating on the
  # env-file lets Frigate run with `cameras = {}` while this stays absent.
  # Create it before setting environmentFile back to a path; see the container
  # preset's environmentFile option. Format: FRIGATE_RTSP_USER=… / FRIGATE_RTSP_PASSWORD=…
  sops.secrets.frigate_rtsp_env = lib.mkIf (config.my.containers.frigate.environmentFile != null) {
    sopsFile = "${inputs.nix-secrets}/nix/per-host/orin-nano.yaml";
  };

  # ─── Frigate data disk (second SSD, nvme1n1) ────────────────
  # Stage-2 unlock for orin_frigate_crypt. disko (disko.nix) formats the disk
  # and declares the /mnt/data/frigate mount, but with initrdUnlock = false it
  # emits nothing to actually open the LUKS device — that's this crypttab entry.
  # It must run in stage 2, not initrd: the keyfile sits on /nix, which lives
  # inside the clevis/Tang-unlocked orin_crypt root and isn't mounted until
  # after initrd. nofail + requires/after nix.mount: never wedge boot if the
  # disk is absent (e.g. pre-provisioning) or /nix is late.
  environment.etc.crypttab.text = ''
    orin_frigate_crypt /dev/disk/by-partlabel/disk-second-frigate /nix/persist/etc/crypt/frigate.key luks,discard,nofail,x-systemd.requires=nix.mount,x-systemd.after=nix.mount
  '';

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

    services.container-updater = {
      enable = true;
      containers =
        let
          excludeFromUpdater = [ ];
          allEnabled = lib.attrNames (lib.filterAttrs (_: v: v.enable or false) config.my.containers);
        in
        lib.subtractLists excludeFromUpdater allEnabled;
    };

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
        # SMOKE-TEST bring-up (2026-08-30): SSD is provisioned, so Frigate is on,
        # but running camera-less and CPU-only to prove the container + the
        # /mnt/data/frigate mount + the web UI (port 5000) come up cleanly.
        #   To go to Phase 1 (GPU TensorRT detection): set enableGPU = true,
        #   jetson = true, detector = "tensorrt" (after building the engine
        #   on-device and confirming the jetsonDevices set), add cameras, create
        #   the frigate_rtsp_env secret and point environmentFile back at it.
        enable = true;
        ip = "${myInventory.network.nodes.frigate.ip}/24";
        detector = "cpu"; # temp — bundled CPU model; target is "tensorrt"
        enableGPU = false; # temp — no GPU passthrough during the smoke test
        jetson = false; # temp — no Tegra /dev/nv* binds (target is true)
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
        # null during the camera-less smoke test (nothing to substitute, and it
        # keeps sops.secrets.frigate_rtsp_env from being required — see the gate
        # near the top of this file). Set back to "/run/secrets/frigate_rtsp_env"
        # when adding real cameras.
        environmentFile = null;
        innerConfig.services.frigate.settings = {
          # MQTT → Home Assistant. Off during the smoke test (hass-pi broker not
          # wired yet); the target values are kept here for when it goes on.
          mqtt = {
            host = "10.85.46.10"; # hass-pi
            enabled = false;
          };

          # No cameras yet. Frigate 0.17 starts fine with an empty set — the web
          # UI comes up and cameras can be added there / here later. The target
          # camera (front_door on the cameras VLAN, 10.0.30.100, DHCP-reserved in
          # openwrt-secrets, {FRIGATE_RTSP_*} env substitution — never inline):
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
