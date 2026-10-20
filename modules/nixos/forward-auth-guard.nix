# forward-auth-guard.nix — only Caddy (and this host) may reach the ports of
# containers whose access control is Caddy's forward_auth.
#
# Inventory nodes with `auth = true` have no login of their own (code-server
# runs with auth = "none", syncthing's GUI has no password, alertmanager has
# none at all, …): Authentik forward-auth in Caddy is their only gate. But
# network-routing.nix routes every host to every container subnet, and
# zero-trust.nix only polices container-to-container traffic, so from any
# LAN device the container port was reachable directly with no login prompt
# (confirmed live on nixos-nvme 2026-09-19 for code-server and syncthing,
# which got a host-local rule then; this generalises it to every such node
# on every nftables host).
#
# Allowed sources:
#   - core-pi's LAN address: Caddy's cross-host traffic arrives masqueraded
#     as that (core-pi masquerades all cbr0 -> end0 egress)
#   - Caddy's own container IP: the same-host case on core-pi
#   - this host's bridge address: host-side administration; NetBird routes
#     to a container (infra/netbird/routes.tf) masquerade to it too, so
#     mesh peers keep their direct path
# Everything else to <node.ip>:<node.port> is dropped. Separate table with
# its own forward hook: a drop in any base chain wins, so this holds
# regardless of zero-trust.nix's early accepts and of
# networking.firewall.filterForward. Hosts without nftables (orin-nano) are
# not covered.
{
  config,
  lib,
  myInventory,
  ...
}:
let
  inherit (config.my.network) subnet hostAddress;
  # Every fleet container subnet is a /24 (network-routing.nix).
  prefix = lib.removeSuffix ".0/24" subnet;
  guarded = lib.filterAttrs (
    _: n: (n.auth or false) && n ? port && lib.hasPrefix "${prefix}." n.ip
  ) myInventory.network.nodes;
  sources = lib.concatStringsSep ", " [
    myInventory.hosts.core-pi.ip
    myInventory.network.nodes.caddy.ip
    hostAddress
  ];
  mkRules = name: n: ''
    ip daddr ${n.ip} tcp dport ${toString n.port} ip saddr { ${sources} } accept comment "forward-auth guard: Caddy -> ${name}"
    ip daddr ${n.ip} tcp dport ${toString n.port} log prefix "FA-GUARD: " drop comment "forward-auth guard: ${name} only via Caddy"'';
in
{
  config = lib.mkIf (config.networking.nftables.enable && guarded != { }) {
    networking.nftables.tables.forward-auth-guard = {
      family = "inet";
      content = ''
        chain forward {
          type filter hook forward priority filter - 1; policy accept;
          ct state established,related accept
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList mkRules guarded)}
        }
      '';
    };
  };
}
