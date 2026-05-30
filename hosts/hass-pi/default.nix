# hass-pi — Raspberry Pi 5
{
  inputs,
  self,
  myInventory,
  ...
}:

{
  imports = [
    inputs.nix-hardware.nixosModules.rpi5
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"
    "${self}/modules/nixos/virtualisation.nix"
    "${self}/modules/nixos/zero-trust.nix"
    "${self}/modules/nixos/pki.nix"
    "${self}/modules/nixos/networking.nix"
    "${self}/modules/nixos/network-routing.nix"
    inputs.nix-presets.nixosModules.monitoring-node
    inputs.nix-presets.nixosModules.home-assistant
  ];

  networking.hostName = "hass-pi";

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXOS_BOOT";
    fsType = "vfat";
  };

  # ─── Networking & Security ──────────────────────────────────
  services.netbird.enable = true;

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

  system.stateVersion = "25.11";
}
