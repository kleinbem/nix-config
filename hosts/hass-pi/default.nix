# hass-pi — Raspberry Pi 5
{
  inputs,
  self,
  myInventory,
  lib,
  pkgs,
  ...
}:

let
  keys = import "${self}/modules/nixos/keys.nix";

in
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    inputs.nix-hardware.nixosModules.rpi5
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"
    "${self}/modules/nixos/persistence.nix"
    "${self}/modules/nixos/virtualisation.nix"
    "${self}/modules/nixos/zero-trust.nix"
    "${self}/modules/nixos/pki.nix"
    "${self}/modules/nixos/networking.nix"
    "${self}/modules/nixos/network-routing.nix"
    "${self}/modules/nixos/services/rpi-eeprom.nix"
    "${self}/modules/nixos/clevis-initrd.nix"
    inputs.nix-presets.nixosModules.monitoring-node
    inputs.nix-presets.nixosModules.home-assistant
  ];

  networking.hostName = "hass-pi";

  users.users.martin.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
    keys.ssh.fido2
    keys.ssh.fido2-backup
  ];

  # --- Stateless Root (Impermanence) ---
  fileSystems = {
    "/" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=2G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    "/var" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=2G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    "/nix".neededForBoot = true;
    "/nix/persist".neededForBoot = true;
  };

  boot.kernelParams = [
    "ip=10.0.0.21::10.0.0.1:255.255.0.0:hass-pi::off"
  ];

  # Enable systemd in initrd for LUKS auto-unlock
  boot.initrd = {
    availableKernelModules = [
      "usb_storage"
      "uas"
      "pcie_brcmstb"
      "nvme"
      "sd_mod"
      "xhci_pci"
      "usbhid"
      "hid_generic"
      "rp1_pci"
      "pinctrl-rp1"
      "clk-rp1"
    ];
    kernelModules = [
      "macb" # Cadence MACB ethernet controller for onboard NIC on RPi5
    ];

    network = {
      enable = true;
      ssh = {
        enable = builtins.pathExists "${inputs.nix-secrets}/initrd/ssh_host_ed25519_key_hass-pi";
        port = 2222;
        authorizedKeys = [
          keys.ssh.yubikey
          keys.ssh.fido2
          keys.ssh.fido2-backup
        ];
        hostKeys = [ "/etc/ssh/ssh_host_ed25519_key_hass-pi" ];
      };
    };
    secrets."/etc/ssh/ssh_host_ed25519_key_hass-pi" = lib.mkForce (
      inputs.nix-secrets + "/initrd/ssh_host_ed25519_key_hass-pi"
    );

    systemd.enable = true;
  };

  # Disko configuration defaults (SSD over USB boots as /dev/sda on the Pi)
  disko.devices.disk.main.device = lib.mkDefault "/dev/sda";
  _module.args.device = "/dev/sda";

  environment.systemPackages = with pkgs; [
  ];

  # Host-specific state persistence
  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/home-assistant"
      "/var/lib/homarr"
    ];
  };

  # ─── Networking & Security ──────────────────────────────────
  networking = {
    useDHCP = false;
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    interfaces = {
      "end0" = {
        ipv4 = {
          addresses = [
            {
              address = "10.0.0.21";
              prefixLength = 16;
            }
          ];
          routes = lib.mkForce [ ];
        };
      };
      "eth0" = {
        ipv4 = {
          addresses = [
            {
              address = "10.0.0.21";
              prefixLength = 16;
            }
          ];
          routes = lib.mkForce [ ];
        };
      };
    };
    defaultGateway = {
      address = "10.0.0.1";
    };
    firewall = {
      enable = true;
      # SSH only over NetBird — not exposed on LAN
      interfaces."wt0".allowedTCPPorts = [ 22 ];
    };
  };

  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "10.85.46.104"; # Orin Nano via NetBird Mesh
        sshUser = "martin";
        systems = [ "aarch64-linux" ];
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
      }
    ];
  };

  my = {
    boot.clevis-initrd = {
      enable = true;
      luksDevice = "hass_crypt";
      hostIp = "10.0.0.21";
      secretFile = ./cryptroot.jwe;
    };
    services.tang.enable = true;
    services.rpi-eeprom.enable = true;
    monitoring.node.enable = true;

    virtualisation = {
      enable = true;
      libvirtd.enable = false;
      podman.enable = true;
      lxc.enable = false;
    };

    network = {
      subnet = "10.85.49.0/24";
      hostAddress = "10.85.49.1";
      externalInterface = "eth0";
    };

    containers = {
      # Smart Home Management
      home-assistant = {
        enable = true;
        ip = "${myInventory.network.nodes.home-assistant.ip}/24";
        hostDataDir = "/var/lib/home-assistant";
        enableUSB = true; # For Zigbee/Z-Wave sticks
        enableBluetooth = true; # For BLE sensors
      };
    };
  };

  # ─── Native Services (Replacing HassOS Add-ons) ───────────────
  services = {
    netbird.enable = true;

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
      allowInterfaces = [ "eth0" ]; # Forward from physical LAN
    };
  };

  virtualisation.oci-containers.containers.homarr = {
    image = "ghcr.io/ajnart/homarr:latest";
    ports = [ "7575:7575" ];
    volumes = [
      "/var/lib/homarr/configs:/app/data/configs"
      "/var/lib/homarr/icons:/app/public/icons"
      "/var/lib/homarr/data:/data"
    ];
  };

  system.stateVersion = "25.11";
}
