# rpi5-node.nix — Shared base module for all Raspberry Pi 5 nodes.
# Provides the complete boot, hardware, networking, and initrd configuration
# common to every RPi5 in the fleet. Host-specific differences (IP, LUKS name,
# services, containers, persistence directories) stay in each host's default.nix.
{
  inputs,
  self,
  config,
  pkgs,
  lib,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
  hostName = config.networking.hostName;
  hostIp = config.my.boot.clevis-initrd.hostIp;
in
{
  # ─── Common Imports ──────────────────────────────────────────
  imports = [
    inputs.nix-hardware.nixosModules.rpi5
    inputs.disko.nixosModules.disko
    "${self}/modules/nixos/base.nix" # foundational, imported by every entry-point bundle
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"
    "${self}/modules/nixos/persistence.nix"
    "${self}/modules/nixos/services/rpi-eeprom.nix"
    "${self}/modules/nixos/clevis-initrd.nix"
    "${self}/modules/nixos/rpi-direct-boot.nix"
    inputs.nix-presets.nixosModules.monitoring-node
  ];

  # ─── Hardware ────────────────────────────────────────────────
  hardware = {
    deviceTree.name = "broadcom/bcm2712-rpi-5-b.dtb";
    bluetooth.enable = true;
    enableRedistributableFirmware = true;
  };

  # Disable TPM2 to prevent 'tpm-crb' module loading errors in initrd
  security.tpm2.enable = lib.mkForce false;
  boot.initrd.systemd.tpm2.enable = lib.mkForce false;

  # ─── SSH Authentication ──────────────────────────────────────
  users.users.martin.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
    keys.ssh.fido2
    keys.ssh.fido2-backup
  ];

  # ─── Stateless Root (Impermanence) ──────────────────────────
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

  # ─── Boot & Initrd ──────────────────────────────────────────
  boot = {
    kernelParams = [
      "ip=${hostIp}::10.0.0.1:255.255.0.0:${hostName}::off"
    ];
    kernelPackages = pkgs.linuxPackages_rpi4;
    initrd = {
      availableKernelModules = [
        "usb_storage"
        "uas"
        "nvme"
        "sd_mod"
      ];
      kernelModules = [
        "macb" # Cadence MACB ethernet controller for onboard NIC on RPi5
        "broadcom" # Broadcom PHY driver (BCM54213PE)
        "phy_generic" # Generic PHY driver fallback
        "pcie_brcmstb" # PCIe controller
        "xhci_pci" # USB host controller
        "usbhid" # USB keyboard
        "hid_generic" # Generic HID driver
        "rp1" # RP1 southbridge (Pi 5 official kernel)
        "reset_raspberrypi"
      ];

      network = {
        enable = true;
        ssh = {
          enable = builtins.pathExists "${inputs.nix-secrets}/initrd/ssh_host_ed25519_key_${hostName}";
          port = 2222;
          authorizedKeys = [
            keys.ssh.yubikey
            keys.ssh.fido2
            keys.ssh.fido2-backup
          ];
          hostKeys = [ "/etc/ssh/ssh_host_ed25519_key_${hostName}" ];
        };
      };
      secrets."/etc/ssh/ssh_host_ed25519_key_${hostName}" = lib.mkForce (
        inputs.nix-secrets + "/initrd/ssh_host_ed25519_key_${hostName}"
      );

      systemd.enable = true;
    };
  };

  # ─── Disko (SSD over USB boots as /dev/sda on the Pi) ───────
  disko.devices.disk.main.device = lib.mkDefault "/dev/sda";
  _module.args.device = "/dev/sda";

  # ─── Networking ──────────────────────────────────────────────
  networking = {
    useDHCP = false;
    resolvconf.enable = lib.mkForce false;
    nameservers = [
      "127.0.0.1"
      "1.1.1.1"
      "8.8.8.8"
    ];
    interfaces."end0" = {
      ipv4 = {
        addresses = [
          {
            address = hostIp;
            prefixLength = 16;
          }
        ];
        routes = lib.mkForce [ ];
      };
    };
    defaultGateway.address = "10.0.0.1";
    firewall = {
      enable = true;
      interfaces."end0".allowedTCPPorts = [ 22 ];
      interfaces."wt0".allowedTCPPorts = [ 22 ];
    };
  };

  # ─── DNS ─────────────────────────────────────────────────────
  environment.etc."resolv.conf".text = ''
    nameserver 127.0.0.1
    nameserver 1.1.1.1
    nameserver 8.8.8.8
    options edns0
  '';

  # ─── Common my.* Settings ───────────────────────────────────
  my = {
    hardware.rpi-direct-boot.enable = true;
    services.tang.enable = true;
    services.rpi-eeprom.enable = true;
    monitoring.node.enable = true;

    virtualisation = {
      enable = true;
      libvirtd.enable = false;
    };

    network.externalInterface = "end0";
  };

  # ─── Common Services ────────────────────────────────────────
  services = {
    netbird.enable = true;
    fstrim.enable = true;
  };

  nix = {
    # distributedBuilds disabled because Orin Nano is offline
  };

  # ─── Storage & Memory ───────────────────────────────────────
  # Swap is now natively handled by disko via a dedicated randomly-encrypted swap partition.

  system.stateVersion = "25.11";
}
