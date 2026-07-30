# hass-pi — Raspberry Pi 5 (Smart Home & Automation)
{
  config,
  lib,
  inputs,
  self,
  myInventory,
  ...
}:
{
  imports = [
    "${self}/modules/nixos/rpi5-node.nix"
    "${self}/modules/nixos/services/container-updater.nix"
    ./disko.nix
    ./secrets.nix
    inputs.nix-presets.nixosModules.home-assistant
    inputs.nix-presets.nixosModules.open-webui
    inputs.nix-presets.nixosModules.agent-zero
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.hermes
    inputs.nix-presets.nixosModules.anythingllm
  ];

  networking = {
    hostName = "hass-pi";
    firewall = {
      allowedTCPPorts = [ 8123 ]; # direct LAN access to HA — see forwardPorts note below
      interfaces."end0".allowedTCPPorts = [ 7654 ]; # Tang
    };
  };

  my = {
    # ─── Clevis LUKS & Network Identity ─────────────────────────
    boot.clevis-initrd = {
      enable = true;
      luksDevice = "hass_crypt";
      hostIp = "10.0.0.21";
      secretFile = "${inputs.nix-secrets}/initrd/cryptroot_hass-pi.jwe";
    };

    # ─── Container Network ──────────────────────────────────────
    network = {
      subnet = "10.85.49.0/24";
      hostAddress = "10.85.49.1";
    };

    services.tang.enable = true;

    # ─── Containers ──────────────────────────────────────────────
    containers = {
      home-assistant = {
        enable = true;
        ip = "${myInventory.network.nodes.home-assistant.ip}/24";
        hostDataDir = "/var/lib/home-assistant";
        enableUSB = true; # For Zigbee/Z-Wave sticks
        enableBluetooth = true; # For BLE sensors
        memoryLimit = "4G";
      };

      open-webui = {
        enable = true;
        ip = "${myInventory.network.nodes.open-webui.ip}/24";
        hostDataDir = "/var/lib/open-webui";
        memoryLimit = "2G";
      };

      openclaw = {
        enable = true;
        ip = "${myInventory.network.nodes.openclaw.ip}/24";
        hostDataDir = "/var/lib/openclaw";
        memoryLimit = "1G";
      };

      agent-zero = {
        enable = true;
        ip = "${myInventory.network.nodes.agent-zero.ip}/24";
        hostDataDir = "/var/lib/agent-zero";
        memoryLimit = "1G";
      };

      anythingllm = {
        enable = true;
        ip = "${myInventory.network.nodes.anythingllm.ip}/24";
        hostDataDir = "/var/lib/anythingllm";
        llmUrl = "https://litellm.internal";
        modelName = "google/gemma-2b"; # Aligned with Orin Nano backend in ai.nix
        memoryLimit = "2G";
      };

      hermes = {
        enable = true;
        ip = "${myInventory.network.nodes.hermes.ip}/24";
        hostDataDir = "/var/lib/hermes";
        memoryLimit = "2G";
        # Same litellm.internal backend as anythingllm above (routes to the
        # Orin Nano's vLLM/Ollama). Pick the actual model with `hermes model`
        # (or `/model custom`, which auto-detects if only one is loaded) —
        # left unset here since litellm's exposed model name isn't verified
        # from this session; adjust model.default in hermes.nix if needed.
        ollamaUrl = "https://litellm.internal/v1";
        secretsFile = config.sops.templates."hermes.env".path;
        discord.enable = true;
      };
    };

    # ─── Standalone container auto-update (ADR 002) ─────────────
    # HA is decoupled from the host generation and refreshed nightly from
    # the CI-published manifest — eval-free on the Pi. Unchanged closures
    # are NOT restarted, so HA only blips when there is an actual update.
    services.container-updater = {
      enable = true;
      containers =
        let
          excludeFromUpdater = [ ];
          allEnabled = lib.attrNames (lib.filterAttrs (_: v: v.enable or false) config.my.containers);
        in
        lib.subtractLists excludeFromUpdater allEnabled;
    };
  };

  # ─── Direct LAN access to Home Assistant ────────────────────
  # The HA container lives on the private cbr0 bridge (10.85.49.10) and is
  # normally reached via Caddy (home.kleinbem.dev). Until the new router/DNS
  # is set up, also forward the Pi's LAN port straight to the container so it's
  # reachable by IP at **http://10.0.0.21:8123** (HTTP, not HTTPS). Safe to drop
  # once DNS/Caddy is the only path again.
  #
  # NOT using `containers.home-assistant.forwardPorts` here — confirmed
  # non-functional for this container. NixOS's forwardPorts implementation
  # passes `--port=` straight through to systemd-nspawn, which tracks its
  # own internally-assigned veth address for the DNAT target. That doesn't
  # necessarily match the address the container's own NixOS network config
  # statically self-assigns (10.85.49.10 here) via `localAddress`+hostBridge,
  # so the forward silently targets the wrong (unused) address inside the
  # container.
  #
  # Plain host-side iptables DNAT to the verified-working address sidesteps
  # that mismatch — iptables, not nftables: hass-pi has
  # networking.nftables.enable = false (classic firewall.enable backend), so
  # `networking.nftables.tables.*` would silently no-op here.
  networking.firewall.extraCommands = ''
    iptables -t nat -A PREROUTING -i end0 -p tcp --dport 8123 -j DNAT --to-destination 10.85.49.10:8123
    iptables -t nat -A POSTROUTING -d 10.85.49.10 -p tcp --dport 8123 -j MASQUERADE
  '';
  networking.firewall.extraStopCommands = ''
    iptables -t nat -D PREROUTING -i end0 -p tcp --dport 8123 -j DNAT --to-destination 10.85.49.10:8123 || true
    iptables -t nat -D POSTROUTING -d 10.85.49.10 -p tcp --dport 8123 -j MASQUERADE || true
  '';

  # ─── Persistence ─────────────────────────────────────────────
  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/home-assistant"
      "/var/lib/homarr"
      "/var/lib/open-webui"
      "/var/lib/openclaw"
      "/var/lib/agent-zero"
      "/var/lib/anythingllm"
      "/var/lib/hermes"
      # Native Services. DynamicUser services keep real state in
      # /var/lib/private/<name> (systemd makes /var/lib/<name> a symlink to it),
      # so we must persist the private path — bind-mounting onto the symlink
      # fails with "mount path not canonical" (see AdGuardHome/matter-server).
      "/var/lib/private/AdGuardHome"
      "/var/lib/node-red"
      "/var/lib/private/esphome"
      "/var/lib/private/matter-server"
      "/var/lib/wyoming"
    ];
  };

  # ─── Native Services (Replacing HassOS Add-ons) ─────────────
  services = {
    adguardhome = {
      enable = true;
      port = 3000;
      openFirewall = true;
    };

    node-red = {
      enable = true;
      openFirewall = true;
    };

    esphome = {
      enable = true;
      openFirewall = true;
    };

    matter-server = {
      enable = true;
    };

    # Voice Pipeline
    wyoming = {
      openwakeword.enable = false; # broken upstream right now
      piper.servers."piper" = {
        enable = true;
        uri = "tcp://0.0.0.0:10200";
        voice = "en_US-lessac-medium";
      };
      faster-whisper.servers."whisper" = {
        enable = true;
        uri = "tcp://0.0.0.0:10300";
        model = "tiny-int8";
        language = "en";
      };
    };

    # Forward mDNS discovery (ESPHome, Cast, Apple TV) to containers
    avahi = {
      enable = true;
      reflector = true;
      allowInterfaces = [ "end0" ]; # Forward from physical LAN
    };
  };

  # ─── Homarr Dashboard (OCI) ─────────────────────────────────
  systemd.tmpfiles.rules = [
    "d /var/lib/homarr 0755 root root - -"
    "d /var/lib/homarr/configs 0755 root root - -"
    "d /var/lib/homarr/icons 0755 root root - -"
    "d /var/lib/homarr/data 0755 root root - -"
  ];

  virtualisation.oci-containers.containers.homarr = {
    image = "ghcr.io/ajnart/homarr:latest";
    ports = [ "7575:7575" ];
    volumes = [
      "/var/lib/homarr/configs:/app/data/configs"
      "/var/lib/homarr/icons:/app/public/icons"
      "/var/lib/homarr/data:/data"
    ];
  };
}
