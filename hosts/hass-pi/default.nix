# hass-pi — Raspberry Pi 5 (Smart Home & Automation)
{
  inputs,
  self,
  lib,
  myInventory,
  ...
}:
{
  imports = [
    "${self}/modules/nixos/rpi5-node.nix"
    ./disko.nix
    ./secrets.nix
    inputs.nix-presets.nixosModules.home-assistant
  ];

  networking.hostName = "hass-pi";

  # hass-pi runs on a native NVMe drive (PCIe HAT), not the USB-SSD enclosure
  # that rpi5-node.nix assumes (it hardcodes /dev/sda). Mounts are unaffected
  # (disko uses stable by-partlabel paths), but a re-provision via disko-install
  # must target the real disk — otherwise it would wipe whatever enumerates as
  # /dev/sda (e.g. a USB stick). Pin it here.
  _module.args.device = lib.mkForce "/dev/nvme0n1";

  # Pin the RPi kernel to the nixpkgs hass-pi already runs (see nixpkgs-rpi-kernel
  # in flake.nix). The current nixpkgs re-hashes linux-rpi-6.12.75 to an aarch64
  # path that's in no binary cache, forcing a ~45min on-Pi compile. Sourcing it
  # from the pinned rev reuses the kernel already in the local store → no build.
  # Userspace still tracks the current nixpkgs (those aarch64 paths ARE on
  # cache.nixos.org). TEMPORARY — remove once the kernel is cached in Attic.
  boot.kernelPackages =
    lib.mkForce
      (import inputs.nixpkgs-rpi-kernel {
        system = "aarch64-linux";
        config.allowUnfree = true;
      }).linuxPackages_rpi4;

  my = {
    deploy.autoUpgrade.enable = true;

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

    virtualisation = {
      podman.enable = true;
      lxc.enable = false;
    };

    services = {
      rpi-eeprom.enable = true; # Auto-apply Pi bootloader EEPROM updates (weekly)
      # Run NetBird's built-in SSH server so YubiKey-less devices can reach this
      # headless node via `netbird ssh hass-pi` (auth = NetBird peer identity).
      # Scope access to your own devices with a NetBird SSH policy in the console.
      netbird.allowServerSsh = true;
    };

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
  };

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
