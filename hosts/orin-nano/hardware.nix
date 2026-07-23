{
  lib,
  inputs,
  self,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
in
{
  # ─── Storage & Memory ───────────────────────────────────────
  zramSwap.enable = true;

  # ─── Jetson-specific hardware ───────────────────────────────
  hardware = {
    graphics.enable = true;
    enableRedistributableFirmware = true;
    # Firmware auto-update disabled: jetpack-nixos rev 441616c builds edk2/OP-TEE
    # capsules, and edk2-pytool-extensions dies on `import pkg_resources`
    # (removed in setuptools 81+). Not cached anywhere (Orin excluded from CI),
    # so it's a hard local build failure. Device firmware is already flashed;
    # re-enable once jetpack-nixos/nixpkgs restores pkg_resources.
    nvidia-jetpack = {
      firmware.autoUpdate = false;
      super = true; # Enable 25W "Super Mode" for Orin Nano Plus
      maxClock = true; # Always run at maximum clock speed
    };
    nvidia.powerManagement.enable = true;
  };

  services = {
    # Set Power Profile to Mode 0 (MAXN / 25W in Super Mode)
    nvpmodel = {
      enable = true;
      profileNumber = 0;
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
          enable = builtins.pathExists "${inputs.nix-secrets}/initrd/ssh_host_ed25519_key_orin-nano";
          port = 2222;
          authorizedKeys = [
            keys.ssh.yubikey
            keys.ssh.fido2
            keys.ssh.fido2-backup
          ];
          hostKeys = [ "/etc/ssh/ssh_host_ed25519_key_orin-nano" ];
        };
      };
      secrets."/etc/ssh/ssh_host_ed25519_key_orin-nano" = lib.mkForce (
        inputs.nix-secrets + "/initrd/ssh_host_ed25519_key_orin-nano"
      );
      systemd = {
        enable = true;
      };
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
  };

  # Spin the fan during the initrd for pre-OS thermal safety: nvfancontrol only
  # starts once the full system boots, so while the Orin waits at the LUKS/Tang
  # prompt (or drops to an initrd emergency shell) the fan is otherwise off.
  # The pwm-tegra + pwm-fan modules are in boot.initrd.availableKernelModules above.
  # 160/255 (~63%): ample airflow for an idle SoC during the short initrd window,
  # noticeably quieter than full blast. nvfancontrol takes over at switch-root.
  # Bump toward 255 if a genuinely-stuck boot (minutes at the prompt) ever runs hot.
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

  # Disko handles all fileSystems (/, /boot, /mnt/data)
  disko.devices.disk.main.device = lib.mkDefault "/dev/nvme0n1";
  _module.args.device = "/dev/nvme0n1"; # Passed to disko.nix function argument
  _module.args.secondDiskDevice = null;
}
