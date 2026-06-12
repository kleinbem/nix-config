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
    # Enable automatic firmware synchronization for future updates
    nvidia-jetpack = {
      firmware.autoUpdate = true;
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
      systemd-boot.enable = lib.mkForce true;
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
      ];

    };
    swraid.enable = false;
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
