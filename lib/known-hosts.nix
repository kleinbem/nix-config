# Pinned port-22 host keys with every name the fleet reaches each host by:
# short name, NetBird FQDN, LAN IP, mesh IP. Read by core.nix
# (programs.ssh.knownHosts) and scripts/generate-infra-yaml.py.
let
  inventory = import ../inventory.nix;
  keys = import ../modules/nixos/keys.nix;
in
builtins.mapAttrs (
  name: publicKey:
  let
    h = inventory.hosts.${name};
  in
  {
    inherit publicKey;
    hostNames = [
      name
      (h.netbirdFqdn or "${h.netbirdName or name}.netbird.cloud")
    ]
    ++ builtins.filter (a: a != null) [
      (h.physicalIp or h.ip or null)
      (h.netbirdIp or null)
    ];
  }
) keys.hostKeys
