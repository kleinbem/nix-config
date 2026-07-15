# rpi5-node.nix — Shared base module for all Raspberry Pi 5 nodes.
# Provides the complete boot, hardware, networking, and initrd configuration
# common to every RPi5 in the fleet. Host-specific differences (IP, LUKS name,
# services, containers, persistence directories) stay in each host's default.nix.
{
  inputs,
  self,
  config,
  lib,
  pkgs,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
  hostName = config.networking.hostName;
  hostIp = config.my.boot.clevis-initrd.hostIp;
  # CI uses --override-input nix-secrets /tmp/dummy-secrets, which lacks the
  # initrd/ subtree. Both consumers below — `network.ssh.enable` and
  # `boot.initrd.secrets` — gate on this, otherwise make-initrd-ng tries to
  # walk a path component that isn't on disk and aborts with
  # "failed to get symlink metadata for <…>/initrd".
  initrdSshKey = "${inputs.nix-secrets}/initrd/ssh_host_ed25519_key_${hostName}";
  hasInitrdSshKey = builtins.pathExists initrdSshKey;
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
  # (the initrd half lives in boot.initrd.systemd below)
  security.tpm2.enable = lib.mkForce false;

  # ─── SSH Authentication ──────────────────────────────────────
  users.users.martin.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
    keys.ssh.fido2
    keys.ssh.fido2-backup
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    keys.ssh.temp-builder
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
    # Shared across every RPi5 node ON PURPOSE: an identical kernel config means
    # a single ~113 MiB kernel derivation both Pis substitute from Attic. Keep
    # all COMPILE-time tuning here; express role-specific tuning as runtime
    # sysctls (below) so it never forks the cached kernel build.
    kernelPatches = [
      {
        name = "rpi5-server-tuning";
        patch = null;
        extraStructuredConfig = with lib.kernel; {
          # ── Scheduling / timers ───────────────────────────────
          # Server throughput over desktop responsiveness, but voluntary (not
          # PREEMPT_NONE) so hass-pi's Zigbee/voice paths stay responsive.
          PREEMPT = no;
          PREEMPT_VOLUNTARY = yes;
          HZ_1000 = no;
          HZ_250 = yes;
          HZ = freeform "250";
          # These nodes are mostly idle — omit ticks on idle CPUs to cut
          # wakeups/jitter and save a little power.
          NO_HZ_IDLE = yes;

          # ── Networking throughput ─────────────────────────────
          # BBR + fq pacing (fq selected via net.core.default_qdisc sysctl).
          TCP_CONG_BBR = yes;
          DEFAULT_BBR = yes;
          NET_SCH_FQ = yes;
          NET_SCH_FQ_CODEL = yes;
          # In-kernel WireGuard so NetBird uses the kernel data path instead of
          # userspace wireguard-go — lower CPU + higher throughput for the
          # Attic-cache-over-NetBird pulls that keep these nodes build-free.
          WIREGUARD = module;

          # ── Containers (podman + nixos-containers) ────────────
          MEMCG = yes;
          MEMCG_SWAP = yes;

          # ── Trim debug overhead (we pay the build cost anyway) ─
          DEBUG_KERNEL = no;
          DEBUG_INFO = no;
        };
      }
    ];
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
          enable = hasInitrdSshKey;
          port = 2222;
          authorizedKeys = [
            keys.ssh.yubikey
            keys.ssh.fido2
            keys.ssh.fido2-backup
          ];
          hostKeys = [ "/etc/ssh/ssh_host_ed25519_key_${hostName}" ];
        };
      };
      secrets = lib.optionalAttrs hasInitrdSshKey {
        "/etc/ssh/ssh_host_ed25519_key_${hostName}" = lib.mkForce initrdSshKey;
      };

      systemd = {
        enable = true;
        # Disable TPM2 to prevent 'tpm-crb' module loading errors in initrd
        tpm2.enable = lib.mkForce false;
      };
    };

    # ─── Kernel runtime tuning (sysctl) ───────────────────────
    # Free to diverge per host if ever needed — sysctls don't fork the cached
    # kernel build the way structuredExtraConfig does.
    kernel.sysctl = {
      # Pair fq pacing with the BBR congestion control compiled in above.
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
      # zram (zstd, see nix-hardware/rpi5.nix) tuning for RAM-limited Pis:
      # compressing a page is cheap, so prefer swapping to zram over evicting
      # page-cache, and disable swap readahead (zram is random-access).
      "vm.swappiness" = 180;
      "vm.page-cluster" = 0;
    };
  };

  # ─── Disko (Raspberry Pi NVMe SSD via PCIe HAT) ─────────────
  # We assume the nodes boot from a native NVMe drive, not a USB-SSD enclosure.
  # Mounts are unaffected since disko uses stable by-partlabel paths, but setting
  # this ensures a re-provision targets the real disk instead of an arbitrary USB.
  disko.devices.disk.main.device = lib.mkDefault "/dev/nvme0n1";
  _module.args.device = "/dev/nvme0n1";

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
    monitoring.node.enable = true;

    services = {
      tang.enable = true;
      rpi-eeprom.enable = true;
      # Run NetBird's built-in SSH server so YubiKey-less devices can reach this
      # headless node via `netbird ssh <host>` (auth = NetBird peer identity).
      # Scope access to your own devices with a NetBird SSH policy in the console.
      netbird.allowServerSsh = true;
    };

    # Pull-deploy; these Pis only ever substitute from Attic (over NetBird) and
    # must never fall back to compiling locally — gate the nightly run on cache
    # reachability and cap its runtime. See modules/nixos/auto-upgrade.nix.
    deploy.autoUpgrade = {
      enable = true;
      requireCache = true;
      # Upgrade the moment promote-production publishes to the secret ntfy
      # topic instead of waiting for the 04:00 timer (which stays as the
      # catch-up path). Requires the host to declare the ntfy_deploy_topic
      # sops secret — the listener is inert until its path exists.
      ntfy.enable = true;
    };

    virtualisation = {
      enable = true;
      libvirtd.enable = false;
      podman.enable = true;
      lxc.enable = false;
    };

    network.externalInterface = "end0";
  };

  # ─── Common Services ────────────────────────────────────────
  services = {
    netbird.enable = true;
    fstrim.enable = true;
  };

  # ─── Extra Packages ─────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    bind.dnsutils
  ];

  nix = {
    # distributedBuilds disabled because Orin Nano is offline
    settings = {
      cores = lib.mkDefault 2; # Limit cores to prevent OOM during kernel builds
      max-jobs = lib.mkDefault 1;
    };
  };

  # Redirect nix builds to the persistent SSD to avoid filling the 2GB tmpfs root.
  # Kernel compilation requires ~15GB of temporary space.
  systemd = {
    services.nix-daemon.environment.TMPDIR = "/nix/persist/tmp/nix-builds";
    tmpfiles.rules = [
      "d /nix/persist/tmp/nix-builds 1777 root root 7d"
    ];
  };

  # ─── Storage & Memory ───────────────────────────────────────
  # Swap is now natively handled by disko via a dedicated randomly-encrypted swap partition.

  system.stateVersion = "25.11";
}
