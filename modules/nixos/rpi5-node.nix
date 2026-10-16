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
  initrdHostKey = "/etc/ssh/ssh_host_ed25519_key_${hostName}";
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
    "${self}/modules/nixos/pull-deploy-node.nix"
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
  # No root authorized_keys here: the only key that was ever wired in
  # (`temp-builder`) had no matching private key anywhere, no script or CI
  # reference, and was labeled "Temporary" — a dead, unrestricted root
  # credential on internet-facing hosts (core-pi fronts the public
  # internet). Real access is martin + sudo (security/sudo.nix) or, for
  # disk unlock, the FIDO2-backed initrd SSH — see caddy-ca-refresh.nix's
  # pattern for what a genuine unattended root-adjacent key should look
  # like (command=-restricted, documented private-key location).

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
          enable = true;
          port = 2222;
          authorizedKeys = [
            keys.ssh.yubikey
            keys.ssh.fido2
            keys.ssh.fido2-backup
          ];
          # extlinux can't append initrd secrets, and NixOS would otherwise
          # bake the key into a world-readable store path. The key is
          # generated on the host (my.hostSecrets), staged on the root-only
          # boot partition below and copied in by initrd-ssh-hostkey.
          hostKeys = [ ];
          ignoreEmptyHostKeys = true;
          extraConfig = "HostKey ${initrdHostKey}";
        };
      };
      supportedFilesystems.vfat = true;

      systemd = {
        enable = true;
        # Disable TPM2 to prevent 'tpm-crb' module loading errors in initrd
        tpm2.enable = lib.mkForce false;

        mounts = [
          {
            what = config.fileSystems."/boot".device;
            where = "/run/bootpart";
            type = "vfat";
            options = "ro,umask=0077";
            unitConfig.DefaultDependencies = false;
          }
        ];
        services.initrd-ssh-hostkey = {
          description = "Copy the initrd SSH host key from the boot partition";
          wantedBy = [ "sshd.service" ];
          before = [ "sshd.service" ];
          requires = [ "run-bootpart.mount" ];
          after = [ "run-bootpart.mount" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
          script = ''
            install -m 0600 /run/bootpart/initrd-secrets/ssh_host_ed25519_key ${initrdHostKey}
          '';
        };
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
    };

    virtualisation = {
      enable = true;
      libvirtd.enable = false;
      podman.enable = true;
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
    # Stage the host-local initrd SSH key on the root-only boot partition,
    # where initrd-ssh-hostkey picks it up on the next boot.
    services.stage-initrd-ssh-hostkey = {
      description = "Stage the initrd SSH host key on the boot partition";
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = [
        "/boot"
        config.my.hostSecrets.dir
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        src=${config.my.hostSecrets.initrdSshKey}
        if [ ! -f "$src" ]; then
          echo "$src is missing; generate it with: just access::host-keygen ${hostName}" >&2
          exit 1
        fi
        install -D -m 0600 "$src" /boot/initrd-secrets/ssh_host_ed25519_key
      '';
    };
    tmpfiles.rules = [
      "d /nix/persist/tmp/nix-builds 1777 root root 7d"
    ];
  };

  # ─── Storage & Memory ───────────────────────────────────────
  # Swap is now natively handled by disko via a dedicated randomly-encrypted swap partition.

  system.stateVersion = "25.11";
}
