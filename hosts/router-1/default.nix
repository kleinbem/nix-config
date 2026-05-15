# router-1 — NixOS in LXC on OpenWrt router
{ inputs, self, ... }:

{
  imports = [
    inputs.nix-hardware.nixosModules.lxc-guest
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

  my.monitoring.node.enable = true;

  system.stateVersion = "25.11";
}
