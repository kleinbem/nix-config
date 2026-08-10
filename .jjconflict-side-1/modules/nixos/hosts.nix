{ lib, myInventory, ... }:

let
  inv = myInventory.network;

  # Function to generate host entries
  # Returns a set like { "10.85.46.100" = [ "silverbullet.local" ]; }
  mkHostEntry =
    name: node:
    let
      domain = "${name}.local";
    in
    lib.nameValuePair node.ip [ domain ];

  hostEntries = lib.mapAttrs' mkHostEntry inv.nodes;

in
{
  # Merge the generated hosts with any existing ones
  networking.hosts = hostEntries;

  # Also ensure MDNS is enabled for resolution if needed,
  # although networking.hosts is usually sufficient for local resolution on the machine itself.
}
