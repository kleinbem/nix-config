# hass-pi — Raspberry Pi 5 (Smart Home & Automation)
{
  inputs,
  self,
  myInventory,
  config,
  lib,
  pkgs,
  ...
}:
let
  # Single source of truth for this host's LUKS volume name — feeds both
  # rpi5-disko.nix (via _module.args below) and my.boot.clevis-initrd.
  luksVolumeName = "hass_crypt";
in
{
  imports = [
    "${self}/modules/nixos/rpi5-node.nix"
    inputs.nix-gantry.nixosModules.host
    inputs.nix-gantry.nixosModules.updater
    "${self}/modules/nixos/rpi5-disko.nix"
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

  _module.args.luksName = luksVolumeName;

  networking = {
    hostName = "hass-pi";
    # UPDATED 2026-09-22: migrated to the nftables firewall backend, same
    # fleet-wide playbook as nixos-nvme/mac-mini/nasbook/orin-nano the same
    # night. Replaces the DNAT workaround below (previously iptables —
    # this host had networking.nftables.enable = false, so
    # networking.nftables.tables.* would have silently no-op'd here) with
    # a native nftables prerouting DNAT chain.
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
    };
  };

  my = {
    # ─── Clevis LUKS & Network Identity ─────────────────────────
    boot.clevis-initrd = {
      enable = true;
      luksDevice = luksVolumeName;
      hostIp = "10.0.0.21";
      secretFile = "${inputs.kleinbem-secrets}/initrd/cryptroot_hass-pi.jwe";
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
  # container. Plain host-side DNAT to the verified-working address
  # sidesteps that mismatch — see the networking.nftables.tables.hass-dnat
  # declaration above.

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
      # openFirewall = true already expressed the intent to be LAN-reachable,
      # but the module's own default (address = "localhost") meant it was
      # only ever listening on loopback — confirmed live 2026-09-20 via
      # `ss -tlnp` showing 127.0.0.1/::1 only, openFirewall doing nothing.
      # Needed anyway now that Home Assistant's panel_iframe (below) embeds
      # this URL directly in a browser tab, which can't reach loopback on
      # a different machine.
      address = "0.0.0.0";
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

  # Upstream ESPHome removed its built-in `dashboard` command (confirmed via
  # `esphome dashboard` erroring "The built-in dashboard has been removed
  # from ESPHome" on 2026.8.0, the version nixpkgs currently ships); the
  # NixOS services.esphome module (nixos/modules/services/home-automation/
  # esphome.nix) hasn't been updated to match and still hardcodes that
  # subcommand, so esphome.service crash-looped on every start. nixpkgs
  # already packages the replacement dashboard tool, esphome-device-builder
  # — override just this ExecStart to use it (same default port 6052,
  # equivalent --host/--port flags) rather than waiting on upstream nixpkgs.
  # Firmware compilation itself is untouched: services.esphome.package
  # (still real esphome) stays on PATH for it via the base module's own
  # `path = [ cfg.package ];`, this just adds the new dashboard binary
  # alongside it.
  systemd.services.esphome = {
    path = [ pkgs.esphome-device-builder ];
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

}
