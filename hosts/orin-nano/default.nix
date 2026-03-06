# orin-nano — NVIDIA Jetson Orin Nano (aarch64)
{ lib, inputs, ... }:

{
  imports = [
    ../../modules/nixos/headless.nix
    ../../modules/nixos/hosts.nix
    # Hardware support from our local hardware flake
    inputs.nix-hardware.nixosModules.orin-nano
  ];

  networking.hostName = "orin-nano";

  # ─── Jetson-specific hardware ───────────────────────────────
  # The Orin Nano uses NVIDIA's JetPack BSP. Full NixOS Jetson support
  # is available via github:anduril/jetpack-nixos — add it as a flake
  # input when you're ready to bootstrap the device.
  #
  # For now, this is a minimal stub that will evaluate correctly.
  hardware.enableRedistributableFirmware = true;

  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible.enable = lib.mkDefault true;
  };

  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/APP";
    fsType = "ext4";
  };

  # ─── AI Edge Services ──────────────────────────────────────
  # TODO: Add edge AI services (inference servers, model runners, etc.)

  system.stateVersion = "25.11";
}
