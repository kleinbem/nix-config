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
        enable = false; # Temporarily disabled: nixpkgs.perl eval error in 26.05 containers — re-enable after first boot
        ip = "10.85.46.126/24";
        modelPath = "/mnt/models/gemma-2-9b-it-q4_k_m.gguf"; # Updated to Gemma as requested
        memoryLimit = "5G";
      };
      frigate = {
        enable = false; # Temporarily disabled for USB provisioning build
        ip = "${myInventory.network.nodes.frigate.ip}/24";
        detector = "tensorrt";
        mediaDir = "/mnt/data/frigate";
        hostDataDir = "/nix/persist/var/lib/frigate"; # persist across tmpfs reboots
        memoryLimit = "3G"; # leave room for llama-cpp + syncthing + system on 8GB host
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
              # Hardware acceleration for stream decoding
              ffmpeg.hwaccel_args = "preset-nvidia-h264";
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
