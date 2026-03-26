# orin-nano — NVIDIA Jetson Orin Nano (aarch64)
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  keys = import ../../modules/nixos/keys.nix;
in
{
  imports = [
    ../../modules/nixos/headless.nix
    ../../modules/nixos/hosts.nix
    ../../users/martin/nixos.nix
    # Hardware support from our local hardware flake
    inputs.nix-hardware.nixosModules.orin-nano
    # Presets
    inputs.nix-presets.nixosModules.vllm
    inputs.nix-presets.nixosModules.monitoring-node
    # Disko configuration
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./secrets.nix
    ../../modules/nixos/persistence.nix
  ];

  networking.hostName = "orin-nano";
  nixpkgs.hostPlatform = "aarch64-linux";

  # ─── Jetson-specific hardware ───────────────────────────────
  # The Orin Nano uses NVIDIA's JetPack BSP via jetpack-nixos.
  hardware = {
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

    # 1. Disable LVM and MDADM globally and in initrd to stop "dm-snapshot" from appearing.
    lvm.enable = lib.mkForce false;

    netbird.enable = true;
    tailscale.enable = false;

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
      systemd.enable = true;

      # 1. Disable LVM and MDADM globally and in initrd to stop "dm-snapshot" from appearing.
      services.lvm.enable = lib.mkForce false;

      # 2. Stop NixOS from adding any "default" PC modules.
      includeDefaultModules = false;

      # 3. Explicitly force ONLY the modules we know exist in the JetPack kernel.
      kernelModules = lib.mkForce [ ];
      availableKernelModules = lib.mkForce [
        "nvme"
        "sd_mod"
        "ext4"
        "dm_crypt"
        "dm_mod"
        "uas"
        "usb_storage"
        "usbhid"
        "tpm_crb" # Compatible with T234
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

  # ─── Performance & RAM ──────────────────────────────────────
  zramSwap.enable = true;

  security.tpm2.enable = true;
  environment.systemPackages = with pkgs; [
    tpm2-tools
    tpm2-tss
  ];

  # Disko handles all fileSystems (/, /boot, /mnt/data)
  disko.devices.disk.main.device = lib.mkDefault "/dev/nvme0n1"; # Default for internal use

  # ─── Virtualization ─────────────────────────────────────────
  virtualisation = {
    libvirtd.enable = true;
    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # ─── AI Edge Services ──────────────────────────────────────
  my = {
    containers.vllm = {
      enable = true;
      ip = "10.85.46.104/24";
      hostDataDir = "/mnt/data/vllm";
      image = "dustynv/vllm:r36.2.0"; # Jetson-optimized vLLM
      gpuMemoryUtilization = 0.65; # Leave 35% for OS and other tasks
      model = "google/gemma-2b";
      memoryLimit = "6G";
      enableGPU = true;
      device = "cuda";
      maxModelLen = 8192;
    };
    monitoring.node.enable = true;
  };

  networking.firewall = {
    enable = true;
    # SSH only over NetBird — not exposed on LAN
    interfaces."wt0".allowedTCPPorts = [ 22 ];
  };

  users.users.martin.openssh.authorizedKeys.keys = [
    keys.ssh.yubikey
  ];

  system.stateVersion = "25.11";
}
