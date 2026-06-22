# router-1 — NixOS in LXC on OpenWrt router
{ inputs, self, ... }:

{
  imports = [
    inputs.nix-hardware.nixosModules.lxc-guest
    "${self}/modules/nixos/base.nix" # foundational, imported by every entry-point bundle
    "${self}/modules/nixos/headless.nix"
    "${self}/modules/nixos/hosts.nix"
    inputs.nix-presets.nixosModules.monitoring-node
  ];

  networking.hostName = "router-1";

  # ─── Networking & Security ──────────────────────────────────
  services.netbird.enable = true;

  networking.firewall = {
    enable = true;
    # SSH only over NetBird — not exposed on LAN
    interfaces."wt0".allowedTCPPorts = [ 22 ];
  };

  my = {
    deploy.autoUpgrade.enable = true;
    monitoring.node.enable = true;
    services.timesync.enable = false; # LXC guests inherit time from the host
  };

  system.stateVersion = "25.11";
}
