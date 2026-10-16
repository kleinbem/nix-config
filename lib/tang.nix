# Tang binding for a host: sss with t = 1 over every OTHER host's Tang server,
# each pinned by its signing-key thumbprint (inventory.nix `tang`).
# Used by scripts/tang-config.sh and the initrd's wait-for-tang list.
let
  inv = import ../inventory.nix;
  others = host: builtins.filter (n: n != host) (builtins.attrNames inv.tang);
in
{
  servers = host: map (n: inv.tang.${n}) (others host);

  binding = host: {
    t = 1;
    pins.tang = map (n: { inherit (inv.tang.${n}) url thp; }) (others host);
  };
}
