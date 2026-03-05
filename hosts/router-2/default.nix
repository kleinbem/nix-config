# router-2 — NixOS in LXC on OpenWrt router
{ inputs, ... }:

{
  imports = [
    inputs.nix-hardware.nixosModules.lxc-guest
    ../../modules/nixos/headless.nix
    ../../modules/nixos/hosts.nix
  ];

  networking.hostName = "router-2";

  # TODO: Add router-specific services here (DNS, firewall rules, monitoring, etc.)

  system.stateVersion = "25.11";
}
