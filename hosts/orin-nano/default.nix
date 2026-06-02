# orin-nano — NVIDIA Jetson Orin Nano (aarch64)
{
  lib,
  pkgs,
  inputs,
  self,
  myInventory,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
  # Initrd gate: poll Tang until it answers before clevis runs, sidestepping the
  # wired-Orin → Wi-Fi-Tang initrd race. MUST be added to
  # boot.initrd.systemd.storePaths (below) or systemd-initrd can't find it → 203/EXEC.
  waitForTang = pkgs.writeShellScript "wait-for-tang" ''
    i=0
    TANG_SERVERS=(${lib.concatMapStrings (s: " \"${s}\"") myInventory.tangServers})
    while [ "$i" -lt 30 ]; do
      for server in "''${TANG_SERVERS[@]}"; do
        if ${pkgs.curl}/bin/curl -fsS -m 2 -o /dev/null "$server/adv"; then
          echo "wait-for-tang: Tang server $server reachable after $i retry(ies)"
          exit 0
        fi
      done
      echo "wait-for-tang: Tang servers not reachable yet ($i)"
      ${pkgs.coreutils}/bin/sleep 1
      i=$((i + 1))
    done
    echo "wait-for-tang: Tang still unreachable; continuing (clevis falls back to passphrase)"
    exit 0
  '';
in
{
  imports = [
    "${self}/modules/nixos/common.nix"
    "${self}/modules/nixos/default.nix"
    "${self}/modules/nixos/hosts.nix"
    "${self}/users/martin/nixos.nix"
    # Hardware support from our local hardware flake
    inputs.nix-hardware.nixosModules.orin-nano
    # Presets
    inputs.nix-presets.nixosModules.ollama
    inputs.nix-presets.nixosModules.llama-cpp
    inputs.nix-presets.nixosModules.frigate
    inputs.nix-presets.nixosModules.syncthing
    inputs.nix-presets.nixosModules.monitoring-node
    # Disko configuration
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./secrets.nix
    "${self}/modules/nixos/persistence.nix"
  ];

  networking.hostName = "orin-nano";
  nixpkgs = {
    hostPlatform = "aarch64-linux";
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
      allowUnsupportedSystem = true;
    };
    overlays = [
      (final: _prev: {
        cudaPackages = final.cudaPackages_12_6;
      })
    ];
  };

  # ─── Jetson-specific hardware ───────────────────────────────
  # The Orin Nano uses NVIDIA's JetPack BSP via jetpack-nixos.
  hardware = {
    graphics.enable = true;
    enableRedistributableFirmware = true;
    # Enable automatic firmware synchronization for future updates
    nvidia-jetpack = {
      firmware.autoUpdate = true;
      super = true; # Enable 25W "Super Mode" for Orin Nano Plus
      maxClock = true; # Always run at maximum clock speed
    };
    nvidia.powerManagement.enable = true;
  };

  services = {
    # Set Power Profile to Mode 0 (MAXN / 25W in Super Mode)
    nvpmodel = {
      enable = true;
      profileNumber = 0;
    };

    # High-performance fan profile for AI workloads
    nvfancontrol.enable = true;

    netbird.enable = true;

    # SSD Health
    fstrim.enable = true;

    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        # Disable 2FA for SSH — colmena deploys non-interactively and cannot
        # provide TOTP. Publickey-only is sufficient on a LAN-only service.
        AuthenticationMethods = lib.mkForce "publickey";
      };
    };
  };

  boot = {
    loader = {
      systemd-boot.enable = lib.mkForce true;
      generic-extlinux-compatible.enable = lib.mkForce false;
    };
    tmp.useTmpfs = true;
    # Enable systemd in initrd for TPM2 auto-unlock (provided by Disko)
    initrd = {
      network = {
        enable = true;
        ssh = {
          enable = builtins.pathExists "${inputs.nix-secrets}/initrd/ssh_host_ed25519_key_orin-nano";
          port = 2222;
          authorizedKeys = [
            keys.ssh.yubikey
            keys.ssh.fido2
            keys.ssh.fido2-backup
          ];
          hostKeys = [ "${inputs.nix-secrets}/initrd/ssh_host_ed25519_key_orin-nano" ];
        };
      };
      systemd = {
        enable = true;
        # Bring up the wired NIC (DHCP) in initrd so clevis can reach the Tang server.
        network = {
          enable = true;
          networks."10-lan" = {
            matchConfig.Name = "en* eth*";
            networkConfig = {
              DHCP = "no";
              Address = "10.0.0.12/16";
              Gateway = "10.0.0.1";
            };
          };
        };

        # Gate clevis on Tang actually being reachable. The Orin is wired and Tang
        # (10.0.0.5) is the Wi-Fi workstation bridged by the router; in the initrd
        # the cross-medium path isn't forwarding the instant the static IP is set,
        # so clevis raced ahead, failed with "Error communicating with server", and
        # fell through to the passphrase prompt. This oneshot polls Tang's /adv until
        # it answers (then clevis succeeds), bounded so a real outage still falls back.
        # systemd-initrd doesn't auto-include ExecStart store paths → pull the gate
        # script + its curl/coreutils/bash closure into the initrd explicitly.
        storePaths = [ waitForTang ];

        services.wait-for-tang = {
          description = "Wait for Tang reachability before clevis LUKS unlock";
          after = [ "systemd-networkd.service" ];
          before = [ "cryptsetup-clevis-orin_crypt.service" ];
          wantedBy = [ "cryptsetup-clevis-orin_crypt.service" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            TimeoutStartSec = 120;
            ExecStart = waitForTang;
          };
        };

        # The gate's own before/wantedBy didn't reliably gate clevis in the initrd,
        # so order the clevis unlock explicitly AFTER the gate. The gate exits 0 even
        # on fall-through, so clevis always runs — by which point Tang is reachable.
        services."cryptsetup-clevis-orin_crypt" = {
          after = [ "wait-for-tang.service" ];
          wants = [ "wait-for-tang.service" ];
        };
      };
      includeDefaultModules = false;
      # lib.mkOverride 0 beats jetpack-nixos's own lib.mkForce so lists don't
      # concatenate and x86-only modules (tpm-tis) are never included.
      kernelModules = lib.mkOverride 0 [
        "phy-tegra-xusb" # Tegra USB PHY — needed before xhci-tegra can init USB
        "xhci-tegra" # Tegra USB 3 host controller (USB-attached NVMe)
        "phy_tegra194_p2u" # PCIe PHY — needed before pcie_tegra194
        "pcie_tegra194" # Tegra PCIe host controller (internal NVMe)
        # Onboard NIC (Realtek RTL8168 via r8168 OOT driver, not nvethernet)
        # Must be in kernelModules (eager) so networkd can bring up enP8p1s0
        # before clevis attempts to contact the Tang server.
        "r8168"
      ];
      availableKernelModules = lib.mkOverride 0 [
        # NVMe (internal PCIe or USB enclosure)
        "nvme"
        "nvme-core"
        # LUKS + LVM
        "dm_crypt"
        "dm_mod"
        # Filesystems
        "ext4"
        # USB storage (for USB-attached NVMe enclosure)
        "uas"
        "usb_storage"
        "usbhid"
        # SCSI
        "sd_mod"
        # TPM — T234 uses CRB interface, not tpm-tis (x86 only)
        "tpm_crb"
      ];
      # Headless LUKS auto-unlock: clevis fetches the key from the Tang server on the LAN
      # during initrd. The LUKS passphrase keyslot stays as the fallback (prompted on
      # serial) if Tang is unreachable, so a Tang/network outage can't lock us out.
      clevis = {
        enable = true;
        useTang = true;
        # pkgs.writeText makes this a build derivation that colmena pushes to the Orin.
        # A plain path (./orin_crypt.jwe) resolves to the git+file:// source, which
        # buildOnTarget never copies — the Orin can't fetch local workstation URLs.
        devices."orin_crypt".secretFile = pkgs.writeText "orin_crypt.jwe" (
          builtins.readFile ./orin_crypt.jwe
        );
      };
    };
    swraid.enable = false;
  };

  # --- Stateless Root (Impermanence) ---
  fileSystems = {
    "/" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=4G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    "/var" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=4G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    # RAM disk (tmpfs) for Frigate cache (significantly reduces SSD wear)
    "/var/lib/frigate/cache" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "nosuid"
        "nodev"
        "noatime"
        "mode=755"
        "size=512M"
      ];
    };
  };

  # ─── Performance & RAM ──────────────────────────────────────
  zramSwap.enable = true;

  security.tpm2.enable = true;
  environment.systemPackages = with pkgs; [
    sops
    age
    libfido2
    clevis # LUKS Tang binding — run `clevis luks bind -d /dev/nvme0n1p2 tang '{"url":"http://10.0.0.5:7654"}'`
    jose # JSON Object Signing and Encryption (clevis dependency)
    inputs.jetpack-nixos.legacyPackages.${pkgs.stdenv.hostPlatform.system}.l4t-tools # Essential: provides tegrastats and L4T utilities
  ];

  # Disko handles all fileSystems (/, /boot, /mnt/data)
  disko.devices.disk.main.device = lib.mkDefault "/dev/nvme0n1";
  _module.args.device = "/dev/nvme0n1"; # Passed to disko.nix function argument
  _module.args.secondDiskDevice = null;

  # ─── Virtualization ─────────────────────────────────────────
  containers.ollama.config = {
    nixpkgs.config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
      allowUnsupportedSystem = true;
    };
  };

  # ─── AI Edge Services ──────────────────────────────────────
  my = {
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
      };
      frigate = {
        enable = true;
        ip = "${myInventory.network.nodes.frigate.ip}/24";
        detector = "tensorrt";
        mediaDir = "/mnt/data/frigate";
        hostDataDir = "/nix/persist/var/lib/frigate"; # persist across tmpfs reboots
        innerConfig.services.frigate.settings = {
          # --- MQTT is required for Home Assistant integration ---
          mqtt = {
            host = "10.85.46.10"; # Pointing to hass-pi for now, assuming MQTT is there or integrated
            enabled = true;
          };

          # --- Sample Camera Configuration ---
          cameras = {
            front_door = {
              ffmpeg.inputs = [
                {
                  path = "rtsp://admin:password@192.168.1.100:554/stream1";
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

  nix.settings.trusted-users = [
    "root"
    "martin"
  ];

  # colmena deploys as martin (PermitRootLogin = "no" in security.nix)
  security.sudo.extraRules = [
    {
      users = [ "martin" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Create persistent syncthing vault and frigate data directories on ext4 /nix
  systemd.tmpfiles.rules = [
    "d /nix/persist/syncthing/nix-config 0755 1000 100 - -"
    "d /nix/persist/var/lib/frigate 0755 root root - -"
  ];

  # systemd-resolved as the local DNS resolver — integrates cleanly with NetBird
  # and provides fallback DNS even when NetBird is disconnected.
  services.resolved = {
    enable = true;
    fallbackDns = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    dnssec = "false";
  };

  networking = {
    # systemd-resolved manages DNS; disable resolvconf to avoid conflict with networking.nix
    resolvconf.enable = lib.mkForce false;
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    # Container bridge — needed by frigate/syncthing nspawn containers
    bridges."cbr0".interfaces = [ ];
    useDHCP = false;
    interfaces = {
      "enP8p1s0" = {
        ipv4 = {
          addresses = [
            {
              address = "10.0.0.12";
              prefixLength = 16;
            }
          ];
          # Suppress static routes from network-routing.nix — other hosts' container
          # subnets (10.85.47-49.0/24) are not routable from the Orin's 10.0.0.x LAN.
          routes = lib.mkForce [ ];
        };
      };
      "cbr0".ipv4.addresses = [
        {
          address = "10.85.46.1";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "10.0.0.1";
      interface = "enP8p1s0";
    };
    nat = {
      enable = true;
      internalInterfaces = [ "cbr0" ];
      externalInterface = "enP8p1s0";
    };
    firewall = {
      enable = true;
      trustedInterfaces = [ "cbr0" ];
      # SSH only over NetBird — not exposed on LAN
      interfaces."wt0".allowedTCPPorts = [ 22 ];
      # Also allow SSH on LAN for emergency access (e.g. before NetBird is running)
      interfaces."enP8p1s0".allowedTCPPorts = [ 22 ];
      extraForwardRules = ''
        iifname "cbr0" oifname "enP8p1s0" accept
        iifname "enP8p1s0" oifname "cbr0" ct state { established, related } accept
      '';
    };
  };

  # Managed via colmena — self-upgrade is not needed and the flake path doesn't
  # exist on the tmpfs root anyway.
  system.autoUpgrade.enable = lib.mkForce false;

  # Disable snapper — /nix is ext4 on this host, btrfs subvolumes cannot be created
  services.snapper.configs = lib.mkForce { };
  systemd.services.snapper-init-persist.enable = lib.mkForce false;

  # ClamAV is irrelevant on a headless edge node with no user-facing file ingestion
  services.clamav = {
    daemon.enable = lib.mkForce false;
    updater.enable = lib.mkForce false;
  };

  users.users = {
    martin.openssh.authorizedKeys.keys = [
      keys.ssh.yubikey
      keys.ssh.fido2
      keys.ssh.fido2-backup
    ];
    root.openssh.authorizedKeys.keys = [
      keys.ssh.yubikey
      keys.ssh.fido2
      keys.ssh.fido2-backup
    ];
  };

  # --- Manual UI Specialisation ---
  # Only active if selected at boot or via 'sudo /run/current-system/specialisation/desktop/bin/switch'
  specialisation.desktop.configuration = {
    environment.etc."specialisation".text = lib.mkForce "desktop";
    my.desktop.lite.enable = true;

    # We KEEP Frigate on because Sway is lite enough!
    my.containers.frigate.enable = lib.mkForce true;

    # Enable a graphical boot splash
    boot.plymouth.enable = true;
  };

  system.stateVersion = "25.11";
  my.services.tang.enable = true;
}
