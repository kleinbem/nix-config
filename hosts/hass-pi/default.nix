# hass-pi — Raspberry Pi 5 (Smart Home & Automation)
{
  inputs,
  self,
  myInventory,
  ...
}:
{
  imports = [
    "${self}/modules/nixos/rpi5-node.nix"
    "${self}/modules/nixos/container-host.nix"
    "${self}/modules/nixos/services/container-updater.nix"
    ./disko.nix
    ./secrets.nix
    inputs.nix-presets.nixosModules.home-assistant
    # openclaw stays here (not moved with the rest of the AI stack to
    # mac-mini 2026-08-05): its pnpm-deps fixed-output derivation hash
    # mismatches its pinned upstream flake (github:openclaw/nix-openclaw)
    # on a from-scratch build — a genuine bug in that external project's
    # own lockfile. This host's copy is unaffected since it's running an
    # already-built/cached artifact (container-updater decouples container
    # updates from full host rebuilds).
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.herdr-remote-client
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

    herdr-remote-client = {
      enable = true;
      serverIp = "10.0.0.5"; # nixos-nvme physical LAN IP (inventory.nix)
    };

    # ─── Container Hosting (via reusable module) ────────────────
    container-host = {
      enable = true;
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

      openclaw = {
        enable = true;
        ip = "${myInventory.network.nodes.openclaw.ip}/24";
        hostDataDir = "/var/lib/openclaw";
        memoryLimit = "1G";
      };
    };

    # ─── Container auto-update (ADR 002) ────────────────────────
    # Configured via container-host module (see above).
    # HA is decoupled from the host generation and refreshed nightly from
    # the CI-published manifest — eval-free on the Pi.
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
  # /var/lib/home-assistant and /var/lib/openclaw are container
  # hostDataDirs — the container-host module auto-derives their
  # persistence entries; listing them here too trips impermanence's
  # duplicate-directory assertion.
  environment.persistence."/nix/persist" = {
    directories = [
      # Native Services. DynamicUser services keep real state in
      # /var/lib/private/<name> (systemd makes /var/lib/<name> a symlink to it),
      # so we must persist the private path — bind-mounting onto the symlink
      # fails with "mount path not canonical" (see matter-server).
      "/var/lib/node-red"
      "/var/lib/private/esphome"
      "/var/lib/private/matter-server"
      "/var/lib/wyoming"
    ];
  };

  # ─── Native Services (Replacing HassOS Add-ons) ─────────────
  services = {
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

}
