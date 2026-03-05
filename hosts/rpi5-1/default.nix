# rpi5-1 — Raspberry Pi 5
{ inputs, ... }:

{
  imports = [
    inputs.nix-hardware.nixosModules.rpi5
    ../../modules/nixos/headless.nix
    ../../modules/nixos/hosts.nix
  ];

  networking.hostName = "rpi5-1";

  # TODO: Add services for this Pi (e.g., home automation, monitoring agent, etc.)

  system.stateVersion = "25.11";
}
