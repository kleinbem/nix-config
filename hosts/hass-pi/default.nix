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
  # Generate list of remote Tang servers (filtering out our own)
  remoteTangServers = lib.filter (s: !lib.hasInfix "10.0.0.21" s) myInventory.tangServers;
  # Initrd gate: poll Tang until it answers before clevis runs, sidestepping the
  # initrd network race. MUST be added to boot.initrd.systemd.storePaths.
  waitForTang = pkgs.writeShellScript "wait-for-tang" ''
    i=0
    TANG_SERVERS=(
      ${lib.concatMapStringsSep "\n      " (s: "\"${s}\"") remoteTangServers}
    )
    while [ "$i" -lt 30 ]; do
      for server in "''${TANG_SERVERS[@]}"; do
        if ${pkgs.curl}/bin/curl -fsS -m 2 -o /dev/null "$server/adv"; then
          echo "wait-for-tang: Tang server $server reachable after $i retry(ies)"
          exit 0
        fi
      done
      echo "wait-for-tang: No Tang servers reachable, retrying in 2s... ($i/30)"
      sleep 2
      i=$((i + 1))
    done
    echo "wait-for-tang: Timeout reached, continuing boot (clevis might fail)"
    exit 0
  '';
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

  # Enable systemd in initrd for LUKS auto-unlock
  boot.initrd = {
    availableKernelModules = [
      "usb_storage"
      "uas"
      "pcie_brcmstb"
      "nvme"
      "sd_mod"
      "xhci_pci"
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

    systemd = {
      enable = true;
      # Bring up the wired NIC in initrd so clevis can reach the Tang server.
      network = {
        enable = true;
        networks."10-lan" = {
          matchConfig.Name = "en* eth*";
          networkConfig = {
            DHCP = "no";
            Address = "10.0.0.21/16";
            Gateway = "10.0.0.1";
          };
        };
      };

      # Gate clevis on Tang actually being reachable.
      storePaths = [ waitForTang ];

      services.wait-for-tang = {
        description = "Wait for Tang reachability before clevis LUKS unlock";
        after = [ "systemd-networkd.service" ];
        before = [ "cryptsetup-clevis-hass_crypt.service" ];
        wantedBy = [ "cryptsetup-clevis-hass_crypt.service" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = 120;
          ExecStart = waitForTang;
        };
      };

      services."cryptsetup-clevis-hass_crypt" = {
        after = [ "wait-for-tang.service" ];
        wants = [ "wait-for-tang.service" ];
      };
    };

    # Clevis LUKS auto-unlock configuration
    clevis = {
      enable = true;
      useTang = true;
      devices."hass_crypt".secretFile = ./cryptroot.jwe;
    };
  };

  # Disko configuration defaults (SSD over USB boots as /dev/sda on the Pi)
  disko.devices.disk.main.device = lib.mkDefault "/dev/sda";
  _module.args.device = "/dev/sda";

  environment.systemPackages = with pkgs; [
    clevis # LUKS Tang binding
    jose # JSON Object Signing and Encryption
  ];

  # Host-specific state persistence
  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/home-assistant"
      "/var/lib/homarr"
    ];
  };

  # ─── Networking & Security ──────────────────────────────────
  networking.firewall = {
    enable = true;
    # SSH only over NetBird — not exposed on LAN
    interfaces."wt0".allowedTCPPorts = [ 22 ];
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
      externalInterface = "end0";
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
      allowInterfaces = [ "end0" ]; # Forward from physical LAN
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
  my.services.tang.enable = true;
}
