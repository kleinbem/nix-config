# Only Caddy (and this host) may reach `auth = true` containers, which rely
# on Caddy's forward_auth and have no login; every host routes to every
# container subnet. Allowed: core-pi's LAN IP (Caddy's cross-host traffic is
# masqueraded to it), Caddy's container IP, this host's bridge IP (also the
# NetBird masquerade source). nftables hosts get their own table (a drop in any
# base chain beats zero-trust.nix's accepts); iptables hosts (orin-nano) a
# chain in FORWARD.
{
  config,
  lib,
  myInventory,
  ...
}:
let
  inherit (config.my.network) subnet hostAddress;
  inherit (config.networking) hostName;
  # Every fleet container subnet is a /24 (network-routing.nix). A node with
  # `host` belongs to that host only: orin-nano reuses nixos-nvme's subnet.
  prefix = lib.removeSuffix ".0/24" subnet;
  onThisHost = n: if n ? host then n.host == hostName else lib.hasPrefix "${prefix}." n.ip;
  guarded = lib.filterAttrs (
    _: n: (n.auth or false) && n ? port && onThisHost n
  ) myInventory.network.nodes;
  sourceList = [
    myInventory.hosts.core-pi.ip
    myInventory.network.nodes.caddy.ip
    hostAddress
  ];
  sources = lib.concatStringsSep ", " sourceList;
  mkRules = name: n: ''
    ip daddr ${n.ip} tcp dport ${toString n.port} ip saddr { ${sources} } accept comment "forward-auth guard: Caddy -> ${name}"
    ip daddr ${n.ip} tcp dport ${toString n.port} log prefix "FA-GUARD: " drop comment "forward-auth guard: ${name} only via Caddy"'';

  chain = "fa-guard";
  mkIptablesRules =
    _: n:
    let
      match = "-d ${n.ip} -p tcp --dport ${toString n.port}";
    in
    lib.concatMapStrings (s: "iptables -w -A ${chain} ${match} -s ${s} -j RETURN\n") sourceList
    + ''
      iptables -w -A ${chain} ${match} -j LOG --log-prefix "FA-GUARD: "
      iptables -w -A ${chain} ${match} -j DROP
    '';
in
{
  config = lib.mkMerge [
    (lib.mkIf (config.networking.nftables.enable && guarded != { }) {
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
    })
    (lib.mkIf
      (!config.networking.nftables.enable && config.networking.firewall.enable && guarded != { })
      {
        networking.firewall.extraCommands = ''
          iptables -w -N ${chain} 2>/dev/null || iptables -w -F ${chain}
          iptables -w -C FORWARD -j ${chain} 2>/dev/null || iptables -w -I FORWARD -j ${chain}
          iptables -w -A ${chain} -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
          ${lib.concatStrings (lib.mapAttrsToList mkIptablesRules guarded)}'';
        networking.firewall.extraStopCommands = ''
          iptables -w -D FORWARD -j ${chain} 2>/dev/null || true
          iptables -w -F ${chain} 2>/dev/null || true
          iptables -w -X ${chain} 2>/dev/null || true
        '';
      }
    )
  ];
}
