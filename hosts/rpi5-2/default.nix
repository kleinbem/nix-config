# rpi5-2 — Raspberry Pi 5
{ inputs, ... }:

{
  imports = [
    inputs.nix-hardware.nixosModules.rpi5
    ../../modules/nixos/headless.nix
    ../../modules/nixos/hosts.nix
    inputs.nix-presets.nixosModules.monitoring-node
  ];

  networking.hostName = "rpi5-2";

  # ─── Networking & Security ──────────────────────────────────
  services.netbird.enable = true;

  networking.firewall = {
    enable = true;
    # SSH only over NetBird — not exposed on LAN
    interfaces."wt0".allowedTCPPorts = [ 22 ];
  };

  my.monitoring.node.enable = true;

  system.stateVersion = "25.11";
}
