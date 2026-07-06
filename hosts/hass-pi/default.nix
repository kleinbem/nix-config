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
  ];

  networking.hostName = "hass-pi";

  my = {
    # ─── Clevis LUKS & Network Identity ─────────────────────────
    boot.clevis-initrd = {
      enable = true;
      luksDevice = "hass_crypt";
      hostIp = "10.0.0.21";
      secretFile = "${./cryptroot.jwe}";
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
  containers.home-assistant.forwardPorts = [
    {
      hostPort = 8123;
      containerPort = 8123;
      protocol = "tcp";
    }
  ];
  networking.firewall.allowedTCPPorts = [ 8123 ];
  networking.firewall.interfaces."end0".allowedTCPPorts = [ 7654 ]; # Tang

  # ─── Persistence ─────────────────────────────────────────────
  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/home-assistant"
      "/var/lib/homarr"
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
