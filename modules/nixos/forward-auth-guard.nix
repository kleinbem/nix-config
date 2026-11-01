# forward-auth-guard.nix — only Caddy (and this host) may reach the ports of
# containers whose access control is Caddy's forward_auth.
#
# `auth = true` nodes have no login of their own, and every host routes to
# every container subnet, so without this any LAN device reaches them directly.
# Allowed: core-pi's LAN address (Caddy's cross-host traffic is masqueraded to
# it), Caddy's container IP, and this host's bridge address (also what NetBird
# routes masquerade to). Own table with its own forward hook, since a drop in
# any base chain wins over zero-trust.nix's accepts. Needs nftables.
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
