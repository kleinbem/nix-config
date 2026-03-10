{
  pkgs,
  lib,
  config,
  inputs,
  myInventory,
  ...
}:

{
  imports = [
    inputs.nix-hardware.nixosModules.nixos-nvme
    inputs.nix-hardware.nixosModules.intel-compute
    ../../modules/nixos/common.nix
    ../../modules/nixos/hosts.nix
    ../../modules/nixos/default.nix
    ../../modules/nixos/options.nix
    ../../users/martin/nixos.nix
    inputs.nix-presets.nixosModules.n8n
    inputs.nix-presets.nixosModules.silverbullet
    inputs.nix-presets.nixosModules.code-server
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.dashboard
    inputs.nix-presets.nixosModules.ollama
    inputs.nix-presets.nixosModules.qdrant
    inputs.nix-presets.nixosModules.playground
    inputs.nix-presets.nixosModules.caddy
    inputs.nix-presets.nixosModules.comfyui
    inputs.nix-presets.nixosModules.langfuse
    inputs.nix-presets.nixosModules.langflow
    inputs.nix-presets.nixosModules.vllm
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.waydroid
    inputs.nix-presets.nixosModules.android-emulator
    ../../modules/nixos/persistence.nix
    ./secrets.nix
    ../../modules/nixos/apps.nix
    ../../modules/nixos/snapper.nix
    ../../modules/nixos/disko.nix
    ../../modules/nixos/data-disk.nix
    inputs.disko.nixosModules.disko
  ];

  # --- Stateless Root / Var ---
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
        "size=8G"
        "mode=755"
      ];
      neededForBoot = true;
    };

    # Persistence Anchor and Images are now managed by disko.nix
    "/nix".neededForBoot = true;
    "/nix/persist".neededForBoot = true;
  };

  # --- Container Configuration ---
  my = {
    containers = {
      n8n = {
        enable = true;
        ip = "${myInventory.network.nodes.n8n.ip}/24";
        hostDataDir = "/var/lib/images/n8n";
        memoryLimit = "6G";
        secretsFile = config.sops.templates."n8n.env".path;
        noteDirs = {
          silverbullet = "${config.my.developDir}/Notes";
          repos = config.my.developDir;
        };
        tls = {
          enable = true;
          serverPort = 5678;
          upstreams = [
            {
              target = myInventory.network.nodes.ollama.ip;
              port = 11434;
            }
            {
              target = myInventory.network.nodes.qdrant.ip;
              port = 6333;
            }
          ];
        };
      };

      silverbullet = {
        enable = true;
        ip = "${myInventory.network.nodes.silverbullet.ip}/24";
        hostDataDir = "${config.my.developDir}/Notes";
        memoryLimit = "512M";
      };

      code-server = {
        enable = true;
        ip = "${myInventory.network.nodes.code-server.ip}/24";
        hostDataDir = config.my.developDir;
        user = config.my.username;
        memoryLimit = "8G"; # IDEs are heavy
      };

      open-webui = {
        enable = true;
        ip = "${myInventory.network.nodes.open-webui.ip}/24";
        hostDataDir = "/var/lib/images/open-webui";
        ollamaUrl = "http://localhost:11434"; # Via mTLS sidecar → Ollama
        vllmUrl = "http://localhost:8000/v1"; # Via mTLS sidecar → vLLM
        memoryLimit = "4G";
        secretsFile = config.sops.templates."openwebui.env".path;
        tls = {
          enable = true;
          serverPort = 8080;
          upstreams = [
            {
              target = myInventory.network.nodes.ollama.ip;
              port = 11434;
            }
            {
              target = myInventory.network.nodes.vllm.ip;
              port = 8000;
            }
            {
              target = myInventory.network.nodes.langfuse.ip;
              port = 3000;
            }
          ];
        };
      };

      dashboard = {
        enable = true;
        ip = "${myInventory.network.nodes.dashboard.ip}/24";
        hostBridgeIp = "10.85.46.1";
        memoryLimit = "1G";
        hostDataDir = "/var/lib/images/dashboard";
        secretsFile = config.sops.templates."homepage.env".path;
      };

      ollama = {
        enable = true;
        ip = "${myInventory.network.nodes.ollama.ip}/24";
        hostDataDir = "/var/lib/images/ollama";
        memoryLimit = "16G";
        tls = {
          enable = true;
          serverPort = 11434;
          upstreams = [ ]; # Ollama doesn't connect to other containers
        };
      };

      qdrant = {
        enable = true;
        ip = "${myInventory.network.nodes.qdrant.ip}/24";
        hostDataDir = "/var/lib/images/qdrant";
        memoryLimit = "2G";
        tls = {
          enable = true;
          serverPort = 6333;
          upstreams = [ ];
        };
      };

      # --- Advanced AI Suite (Disabled by default, Safely Persistent) ---
      comfyui = {
        enable = false;
        ip = "${myInventory.network.nodes.comfyui.ip}/24";
        hostDataDir = "/var/lib/images/comfyui";
      };
      langflow = {
        enable = false;
        ip = "${myInventory.network.nodes.langflow.ip}/24";
        hostDataDir = "/var/lib/images/langflow";
      };
      langfuse = {
        enable = false;
        ip = "${myInventory.network.nodes.langfuse.ip}/24";
        hostDataDir = "/var/lib/images/langfuse";
      };
      vllm = {
        enable = false;
        ip = "${myInventory.network.nodes.vllm.ip}/24";
        hostDataDir = "/var/lib/images/vllm";
      };
      openclaw = {
        enable = false;
        ip = "${myInventory.network.nodes.openclaw.ip}/24";
        hostDataDir = "/var/lib/images/openclaw";
      };
      agent-zero = {
        enable = false;
        ip = "${myInventory.network.nodes.agent-zero.ip}/24";
        hostDataDir = "/var/lib/images/agent-zero";
        ollamaUrl = "http://localhost:11434"; # Via mTLS sidecar → Ollama
        tls = {
          enable = true;
          serverPort = 50001;
          upstreams = [
            {
              target = myInventory.network.nodes.ollama.ip;
              port = 11434;
            }
          ];
        };
      };
      # ------------------------------------------------------------------

      playground = {
        enable = true;
        ip = "${myInventory.network.nodes.playground.ip}/24";
        hostDataDir = "/var/lib/images/playground";
        user = config.my.username;
        memoryLimit = "8G";
      };
      caddy = {
        enable = true;
        ip = "${myInventory.network.nodes.caddy.ip}/24";
        hostDataDir = "/var/lib/images/caddy";
        memoryLimit = "512M";
        tls = {
          enable = true;
          serverPort = 0; # Caddy manages its own TLS, sidecar inbound not needed
          upstreams = [ ]; # Caddy connects to mTLS containers via helpers
        };
      };
    };

    desktop.enable = true;
    virtualisation.enable = true;
    services = {
      printing.enable = true;
      glances.enable = true;
    };
  };

  # --- Persistence & System Services ---
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    SystemMaxFileSize=50M
    MaxRetentionSec=1month
  '';

  programs.waydroid-setup.enable = false;
  home-manager.users.${config.my.username} = import ../../users/martin/home.nix;

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    initrd = {
      availableKernelModules = [ "ahci" ];
      kernelModules = [
        "usbhid"
        "hid_generic"
      ];
      systemd.enable = true;
    };
    loader = {
      systemd-boot.enable = false;
      systemd-boot.configurationLimit = 30;
      efi.canTouchEfiVariables = true;
    };
    lanzaboote = {
      enable = true;
      pkiBundle = "/nix/persist/var/lib/sbctl";
    };
    kernelParams = [
      "i915.enable_guc=2"
      "i915.enable_fbc=1"
    ];
    tmp.useTmpfs = true;
    tmp.tmpfsSize = "8G";

    # Cross-compilation: build aarch64-linux on this x86_64 host
    binfmt.emulatedSystems = [ "aarch64-linux" ];
  };

  # IMAGE STATE STORAGE
  systemd.tmpfiles.rules = [
    "d /var/lib/images 0755 root root - -" # Create parent, non-recursive
    "d /var/lib/images/n8n 0755 root root - -"
    "z /var/lib/images/n8n 0755 root root - -" # Recursively fix ONLY n8n
    "d /var/lib/images/dashboard 0755 root root - -"
    "d /var/lib/images/playground 0755 martin users - -"
    "z /var/lib/images/playground 0755 martin users - -" # Ensure you own your playground
    "d /var/lib/images/caddy 0755 root root - -"
    "d /var/lib/images/lmstudio 0750 martin users - -"
    "z /var/lib/images/lmstudio 0750 martin users - -"
  ];

  hardware = {
    cpu.intel.updateMicrocode = true;
    enableAllFirmware = true;
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        libvdpau-va-gl
      ];
    };
  };

  networking = {
    hostName = "nixos-nvme";
    networkmanager = {
      enable = true;
      plugins = [ pkgs.networkmanager-openvpn ];
    };
    firewall = {
      enable = true;
      # Zero Trust: Tailscale is NOT blanket-trusted.
      # Only specific ports are open over the tunnel.
      interfaces."tailscale0".allowedTCPPorts = [
        22 # SSH
        443 # Caddy HTTPS (access all services via reverse proxy)
        9091 # Cockpit
      ];
      allowedTCPPortRanges = [
        {
          from = 1714;
          to = 1764;
        } # KDE Connect (Valent)
      ];
      allowedUDPPortRanges = [
        {
          from = 1714;
          to = 1764;
        } # KDE Connect (Valent)
      ];
    };
    nftables.enable = true;
  };

  services = {
    android-desktop-emulator = {
      enable = true;
      user = config.my.username;
    };
    tailscale.enable = true;
    pcscd.enable = true;
    fprintd.enable = true;
    udev.packages = [
      pkgs.yubikey-personalization
      pkgs.libfido2
    ];
    fwupd.enable = true;
    btrfs.autoScrub = {
      enable = true;
      interval = "weekly";
      fileSystems = [
        "/home"
        "/nix"
      ];
    };
    fstrim.enable = true;
  };

  security.pki.certificateFiles = [ ./../../pki/caddy-root.crt ];

  environment.systemPackages = with pkgs; [
    sops
    age
    age-plugin-yubikey
    age-plugin-tpm
    libfido2
    pam_u2f
    sbctl
    niv
    yubikey-personalization
    android-tools
    scrcpy
    valent
  ];

  system.stateVersion = "25.11";
}
