# orin-nano-bootstrap — Jetson Orin Nano minimal first-boot commissioning image.
#
# Goal: get to SSH as fast as possible. No LUKS, no LVM, no impermanence, no
# services. Once the Orin is reachable, deploy the real orin-nano config from
# the device itself to avoid x86_64 → aarch64 cross-compilation pain.
{
  lib,
  pkgs,
  inputs,
  self,
  ...
}:
let
  keys = import "${self}/modules/nixos/keys.nix";
in
{
  imports = [
    inputs.nix-hardware.nixosModules.orin-nano
    inputs.disko.nixosModules.disko
    ./disko.nix
  ];

  networking.hostName = "orin-nano-bootstrap";

  nixpkgs = {
    hostPlatform = "aarch64-linux";
    config.allowUnfree = true;
  };

  hardware.nvidia-jetpack.firmware.autoUpdate = false;

  boot = {
    loader = {
      systemd-boot.enable = lib.mkForce true;
      generic-extlinux-compatible.enable = lib.mkForce false;
      efi.canTouchEfiVariables = lib.mkForce false;
    };
    tmp.useTmpfs = false;
    swraid.enable = false;
    kernelParams = [
      "console=ttyTHS0,115200n8"
      "console=tty0"
    ];
    kernelModules = lib.mkOverride 0 [ ];
    initrd = {
      systemd.emergencyAccess = true;
      includeDefaultModules = false;
      # Force-load USB PHY + host controller before udev runs so the USB SSD
      # is already enumerated when systemd starts looking for disk-main-root.
      kernelModules = lib.mkOverride 0 [
        "phy-tegra-xusb" # Tegra USB PHY — xhci-tegra won't bring up ports without it
        "xhci-tegra" # Tegra xHCI host controller
      ];
      availableKernelModules = lib.mkOverride 0 [
        # Storage
        "nvme"
        "sd_mod"
        "ext4"
        # USB storage protocols
        "uas"
        "usb_storage"
        "usbhid"
        # USB Type-C
        "ucsi_ccg"
        "typec_ucsi"
        "typec"
        # PCIe (needed for NVMe and Ethernet on Orin)
        "phy_tegra194_p2u"
        "pcie_tegra194"
      ];
    };
  };

  services = {
    openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
    };
    fstrim.enable = true;
    avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
      };
    };
  };

  # SSH reachable on any interface — no netbird/VPN needed at this stage
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  users.users = {
    root = {
      openssh.authorizedKeys.keys = [ keys.ssh.yubikey ];
      # Temporary plain-text password for emergency shell access during commissioning
      initialPassword = "nixos";
    };
    martin = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [ keys.ssh.yubikey ];
    };
  };

  security.sudo.wheelNeedsPassword = false;

  nix = {
    settings = {
      trusted-users = [
        "root"
        "martin"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
  ];

  # Target device — override at install time via --argstr if needed
  disko.devices.disk.main.device = lib.mkDefault "/dev/sdb";

  system.stateVersion = "25.11";
}
