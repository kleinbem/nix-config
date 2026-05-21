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
      efi.canTouchEfiVariables = true;
    };
    tmp.useTmpfs = false;
    swraid.enable = false;
    initrd = {
      includeDefaultModules = false;
      availableKernelModules = [
        "nvme"
        "sd_mod"
        "ext4"
        "uas"
        "usb_storage"
        "usbhid"
      ];
    };
  };

  services = {
    openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
    };
    fstrim.enable = true;
  };

  # SSH reachable on any interface — no netbird/VPN needed at this stage
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  users.users = {
    root.openssh.authorizedKeys.keys = [ keys.ssh.yubikey ];
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
