# hass-pi — Raspberry Pi 5 (Smart Home & Automation)
{
  inputs,
  self,
  myInventory,
  config,
  lib,
  pkgs,
  secretFile,
  ...
}:
let
  # Single source of truth for this host's LUKS volume name — feeds both
  # rpi5-disko.nix (via _module.args below) and my.boot.clevis-initrd.
  luksVolumeName = "hass_crypt";
  hostSops = secretFile "nix/per-host/hass-pi.yaml";
  hasNodeRedAdminHash =
    builtins.pathExists hostSops
    && lib.hasInfix "\nnode_red_admin_hash:" ("\n" + builtins.readFile hostSops);
in
{
  imports = [
    "${self}/modules/nixos/rpi5-node.nix"
    inputs.nix-gantry.nixosModules.host
    inputs.nix-gantry.nixosModules.host-persistence
    inputs.nix-gantry.nixosModules.updater
    "${self}/modules/nixos/rpi5-disko.nix"
    ./secrets.nix
    ./esphome-secrets.nix
    inputs.nix-presets.nixosModules.home-assistant
    # openclaw stays here rather than on mac-mini: its pnpm-deps hash in
    # nix-openclaw mismatches on a from-scratch build, and this host runs an
    # already-cached build.
    inputs.nix-presets.nixosModules.openclaw
    inputs.nix-presets.nixosModules.herdr-remote-client
  ];

  _module.args.luksName = luksVolumeName;

  # bcrypt hash for Node-RED's editor login (see services.node-red below).
  sops.secrets.node_red_admin_hash = lib.mkIf hasNodeRedAdminHash {
    sopsFile = hostSops;
    owner = config.services.node-red.user;
  };

  networking = {
    hostName = "hass-pi";
    # nftables must be on, or nftables.tables.* below silently does nothing.
    nftables.enable = true;
    nftables.tables.hass-dnat = {
      family = "ip";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          iifname "end0" tcp dport 8123 dnat to 10.85.49.10:8123
        }
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          ip daddr 10.85.49.10 tcp dport 8123 masquerade
        }
      '';
    };
    firewall = {
      backend = "nftables";
      allowedTCPPorts = [ 8123 ]; # direct LAN access to HA — see forwardPorts note below
      interfaces."end0".allowedTCPPorts = [ 7654 ]; # Tang
      # Only the container bridge may reach the host-side Matter server
      # websocket, the OTBR REST API and the Wyoming voice servers; Home
      # Assistant talks to them at ${hostAddress} from inside its container.
      interfaces."cbr0".allowedTCPPorts = [
        5580 # matterjs-server
        8081 # openthread-border-router REST
        10200 # wyoming-piper
        10300 # wyoming-faster-whisper
      ];
    };
  };

  my = {
    # External dead-man's switch (modules/nixos/heartbeat.nix): <host>-alive
    # every 5 min + a ping per backup job; missing pings alert from
    # healthchecks.io, outside the fleet. Always-on hosts only.
    heartbeat.enable = true;
    # comin pull-deploy replaces autoUpgrade. requireCache: this host never
    # compiles a closure; CI builds its toplevel before promote moves the branch.
    deploy = {
      autoUpgrade.enable = false;
      comin = {
        enable = true;
        requireCache = true;
      };
    };
    # ─── Clevis LUKS & Network Identity ─────────────────────────
    boot.clevis-initrd = {
      enable = true;
      luksDevice = luksVolumeName;
      hostIp = "10.0.0.21";
      secretFile = secretFile "initrd/cryptroot_hass-pi.jwe";
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
      manifestUrl = "https://github.com/kleinbem/nix-config/releases/download/container-manifest/manifest.json";
      # nix-gantry defaults this to false; this fleet always has impermanence.
      enablePersistence = true;
    };

    services.tang.enable = true;
    # Backups: nix-presets' backup-engine, fleet wiring in
    # modules/nixos/backup.nix. home-assistant and tang register their own
    # items. Secrets: backup_r2_rclone_config (nix/per-host/hass-pi.yaml),
    # rclone_config/restic_password/ntfy_alert_topic (nix/shared.yaml).
    backup.enable = true;

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
  # HA is normally reached via Caddy (home.kleinbem.dev). Until the new
  # router/DNS is in place, hass-dnat above also exposes http://10.0.0.21:8123.
  # Not forwardPorts: systemd-nspawn DNATs to its own veth address, not the
  # container's static 10.85.49.10, so the forward hits nothing.

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
      # Static `esphome` user (not DynamicUser), so the state is the plain
      # path; /var/lib/private/esphome was the old DynamicUser location.
      "/var/lib/esphome"
      "/var/lib/private/matterjs-server"
      "/var/lib/wyoming"
    ];
  };

  # ─── Native Services (Replacing HassOS Add-ons) ─────────────
  services = {
    node-red = {
      enable = true;
      openFirewall = true;
      # The editor has no login by default and its exec nodes run commands,
      # so adminAuth turns on once `node_red_admin_hash` (bcrypt, from
      # `node-red admin hash-pw`) is in nix/per-host/hass-pi.yaml. Gated on
      # the key name because sops-nix fails activation on a missing key.
      configFile = pkgs.writeText "node-red-settings.js" ''
        const base = require("${config.services.node-red.package}/lib/node_modules/node-red/packages/node_modules/node-red/settings.js");
        ${lib.optionalString hasNodeRedAdminHash ''
          base.adminAuth = {
            type: "credentials",
            users: [{
              username: "martin",
              password: require("fs").readFileSync("${config.sops.secrets.node_red_admin_hash.path}", "utf8").trim(),
              permissions: "*",
            }],
          };
        ''}
        module.exports = base;
      '';
    };

    esphome = {
      enable = true;
      openFirewall = true;
      # The module defaults to localhost, which makes openFirewall useless;
      # HA's panel_iframe also loads this URL from other machines' browsers.
      address = "0.0.0.0";
    };

    # Matter controller for Home Assistant's matter integration
    # (ws://10.85.49.1:5580/ws from inside the container). Not
    # python-matter-server: it is archived and dies at start-up with
    # cryptography 49.
    matterjs-server = {
      enable = true;
      listenAddress = "10.85.49.1";
      bluetoothSupport = true; # commission over BLE with the Pi's adapter
    };

    # Thread border router for the SkyConnect dongle. ConditionPathExists below
    # keeps otbr-agent inactive (not failed) until the device appears. HA's
    # otbr/thread integrations point at http://10.85.49.1:8081.
    openthread-border-router = {
      enable = true;
      backboneInterfaces = [ "end0" ];
      rest.listenAddress = "10.85.49.1";
      radio = {
        device = "/dev/serial/by-id/usb-Nabu_Casa_SkyConnect_v1.0_3e82cd21b5d8ed11b11a796162c613ac-if00-port0";
        baudRate = 460800; # SkyConnect / Connect ZBT-1 firmware default
        flowControl = true;
      };
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
        # tiny is the least accurate model; base is still fast enough on the Pi 5.
        model = "base-int8";
        language = "en";
      };
    };

    # Forward mDNS discovery (ESPHome, Cast, Apple TV) to containers
    avahi = {
      enable = true;
      settings = {
        reflector.enable-reflector = true;
        # The reflector forwards between the interfaces avahi runs on, so it
        # needs the container bridge too, or HA (Cast, zeroconf discovery)
        # never sees the LAN's announcements.
        server.allow-interfaces = [
          "end0"
          "cbr0"
        ];
      };
    };
  };

  systemd = {
    # See services.openthread-border-router above: stay inactive until the
    # SkyConnect dongle is plugged in rather than failing on a missing radio.
    services.otbr-agent.unitConfig.ConditionPathExists =
      config.services.openthread-border-router.radio.device;

    # ESPHome 2026.8 removed `esphome dashboard`, which the NixOS module still
    # runs; use esphome-device-builder instead (same port and flags). esphome
    # itself stays on PATH for firmware builds.
    services.esphome = {
      path = [ pkgs.esphome-device-builder ];
      # Link the device configs in ./esphome into the state dir so this repo
      # stays the source of truth. Done in preStart, not tmpfiles: tmpfiles
      # refuses to write into another user's directory ("unsafe path
      # transition"). secrets.yaml comes from ./esphome-secrets.nix.
      preStart = lib.concatMapStrings (f: "ln -sfn ${./esphome}/${f} /var/lib/esphome/${f}
") (
        builtins.filter (f: lib.hasSuffix ".yaml" f) (builtins.attrNames (builtins.readDir ./esphome))
      );
      serviceConfig.ExecStart = lib.mkForce (
        let
          cfg = config.services.esphome;
          args =
            if cfg.enableUnixSocket then
              "--socket /run/esphome/esphome.sock"
            else
              "--host ${cfg.address} --port ${toString cfg.port}";
        in
        "${pkgs.esphome-device-builder}/bin/esphome-device-builder ${args} /var/lib/esphome"
      );
    };
  };

}
