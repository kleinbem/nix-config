{
  config,
  lib,
  self,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
in
{
  # ─── Storage & Memory ───────────────────────────────────────
  # Cap ZRAM to 25% of RAM (~1.8 GB) so compressed pages don't starve physical
  # memory when Frigate + LLM are resident; let 16 GB NVMe swap take large build spikes.
  zramSwap = {
    enable = true;
    memoryPercent = 25;
    algorithm = "zstd";
  };

  # ─── Jetson-specific hardware ───────────────────────────────
  hardware = {
    graphics.enable = true;
    enableRedistributableFirmware = true;
    # firmware.autoUpdate: a switch on a firmware mismatch stages the UEFI
    # capsule, and the next reboot flashes the inactive A/B slot (falling back
    # if it fails). Never reboots by itself. The capsule comes from our Attic,
    # not anduril.cachix.org (built against our nixpkgs, hashes differ).
    # Skip it for one deploy with JETPACK_NIXOS_SKIP_CAPSULE_UPDATE=1.
    nvidia-jetpack = {
      # majorVersion = "7"; # Switch when QSPI firmware is flashed over USB-C
      firmware.autoUpdate = true;
      super = true; # Enable 25W "Super Mode" for Orin Nano Plus
      maxClock = true; # Always run at maximum clock speed
    };
    nvidia.powerManagement.enable = true;
  };

  services = {
    # Power profile 2 = MAXN_SUPER (Super Mode without a power cap; 0 = 15W,
    # 1 = 25W). Switching to it needs no reboot.
    nvpmodel = {
      enable = true;
      profileNumber = 2;
    };
    # High-performance fan profile for AI workloads
    nvfancontrol.enable = true;
    # SSD Health
    fstrim.enable = true;
  };

  boot = {
    loader = {
      systemd-boot = {
        enable = lib.mkForce true;
        # Cap ESP boot entries. The 1 GiB ESP filled with ~30 stale
        # per-generation kernels/initrds because old entries weren't pruned,
        # which eventually orphaned the loader. Bound it so it can't refill.
        configurationLimit = 10;
      };
      generic-extlinux-compatible.enable = lib.mkForce false;
    };
    tmp.useTmpfs = true;
    # Enable systemd in initrd for TPM2 auto-unlock (provided by Disko)
    initrd = {
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
          hostKeys = [ "/etc/ssh/ssh_host_ed25519_key_orin-nano" ];
        };
      };
      secrets."/etc/ssh/ssh_host_ed25519_key_orin-nano" = lib.mkForce config.my.hostSecrets.initrdSshKey;
      includeDefaultModules = false;
      # lib.mkOverride 0 beats jetpack-nixos's own lib.mkForce so lists don't
      # concatenate and x86-only modules (tpm-tis) are never included.
      kernelModules = lib.mkOverride 0 [
        "phy-tegra-xusb" # Tegra USB PHY — needed before xhci-tegra can init USB
        "xhci-tegra" # Tegra USB 3 host controller (USB-attached NVMe)
        "phy_tegra194_p2u" # PCIe PHY — needed before pcie_tegra194
        "pcie_tegra194" # Tegra PCIe host controller (internal NVMe)
        # Onboard NIC (Realtek RTL8168 via r8168 OOT driver, not nvethernet)
        # Must be in kernelModules (eager) so networkd can bring up enP8p1s0
        # before clevis attempts to contact the Tang server.
        "r8168"
      ];
      availableKernelModules = lib.mkOverride 0 [
        # NVMe (internal PCIe or USB enclosure)
        "nvme"
        "nvme-core"
        # LUKS + LVM
        "dm_crypt"
        "dm_mod"
        # Filesystems
        "ext4"
        # USB storage (for USB-attached NVMe enclosure)
        "uas"
        "usb_storage"
        "usbhid"
        # SCSI
        "sd_mod"
        # TPM — T234 uses CRB interface, not tpm-tis (x86 only)
        "tpm_crb"
        # PWM fan (my.boot.initrd-fan): controller then hwmon driver, so the fan
        # can be spun up while the machine waits at the LUKS/Tang prompt. This
        # list is mkOverride 0, which would otherwise drop the module's own
        # availableKernelModules addition — so they must be listed here.
        "pwm-tegra"
        "pwm-fan"
      ];

    };
    swraid.enable = false;

    # Headless, no audio: the Tegra audio graph card fails with EBUSY on every
    # boot. Blacklisted only to keep dmesg and `systemctl --failed` clean.
    blacklistedKernelModules = [ "snd_soc_tegra_audio_graph_card" ];
  };

  # nvfancontrol only starts after switch-root, so the fan would be off while
  # waiting at the LUKS/Tang prompt. 160/255 is enough for an idle SoC; raise
  # it if a boot stuck at the prompt ever runs hot.
  my.boot.initrd-fan = {
    enable = true;
    pwm = 160;
  };

  # --- Stateless Root (Impermanence) ---
  fileSystems = {
    "/" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=4G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    "/var" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=4G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    # RAM disk (tmpfs) for Frigate cache (significantly reduces SSD wear)
    "/var/lib/frigate/cache" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "nosuid"
        "nodev"
        "noatime"
        "mode=755"
        "size=512M"
      ];
    };
  };

  security.tpm2.enable = true;

  # Disko handles all fileSystems (/, /boot, /mnt/data, and /mnt/data/frigate
  # on the second SSD — see disko.nix + the stage-2 crypttab in services.nix)
  disko.devices.disk.main.device = lib.mkDefault "/dev/nvme0n1";
  _module.args.device = "/dev/nvme0n1"; # Passed to disko.nix function argument
  # Frigate SSD: LUKS → ext4 → /mnt/data/frigate, keyfile-unlocked in stage 2
  # (see disko.nix). A new disk needs /nix/persist/etc/crypt/frigate.key and
  # disko's format step scoped to partlabel disk-second-frigate before deploy.
  _module.args.secondDiskDevice = "/dev/nvme1n1";
}
