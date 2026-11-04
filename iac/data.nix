# Projects personas.nix and inventory.nix to JSON for the nix/infra OpenTofu
# roots, which can't import Nix: nix/infra/personas.json and inventory.json.
# Regenerate with `nix/tools/gen-iac-data.sh`; `nix/tools/check-iac-data.sh`
# catches drift in the committed copies.
{
  lib,
  inventory ? import ../inventory.nix,
  personas ? import ../personas.nix,
  # kleinbem-secrets/personas/contact.nix (plain Nix in a private repo).
  # Empty gives a public-only eval without the PII fields.
  contact ? { },
}:
let
  # Public persona layer merged with the private contact layer. Consumers
  # read `.email` and `.dkim_pubkey_b64`.
  personasJson = lib.mapAttrs (name: p: p // (contact.${name} or { })) personas;

  hostNames = lib.attrNames inventory.hosts;

  # NetBird mesh group membership (inventory.meshGroups).
  meshGroups = inventory.meshGroups or { };
  groupNames = lib.attrNames meshGroups;

  unknownRefs = lib.concatMap (
    g: map (h: "${g}/${h}") (lib.filter (h: !(lib.elem h hostNames)) meshGroups.${g})
  ) groupNames;

  cacheGroup = meshGroups.cache or [ ];

  # Group members as NetBird peer names: the netbird root looks peers up by
  # name, which can differ from the inventory name (e.g. phone).
  meshPeers = lib.mapAttrs (_: map (h: inventory.hosts.${h}.netbirdName or h)) meshGroups;

  # Names NetBird DNS answers with the Caddy peer: every `meshOnly` node's
  # domain + extraDomains. Read by netbird/dns.tf and, through this file,
  # by modules/nixos/ai-hardening.nix's dnsmasq forwards.
  meshOnlyFqdns = lib.sort lib.lessThan (
    lib.concatMap (n: [ n.domain ] ++ n.extraDomains or [ ]) (
      lib.filter (n: n.meshOnly or false) (lib.attrValues inventory.network.nodes)
    )
  );

  inventoryJson = {
    # Minimal host projection — only what the netbird root needs.
    hosts = lib.mapAttrs (_: h: {
      tags = h.tags or [ ];
      ip = h.ip or null;
      netbirdIp = h.netbirdIp or null;
      system = h.system or null;
      type = h.type or null;
    }) inventory.hosts;

    mesh = meshPeers // {
      # The one caddy/attic entrypoint peer that cache.kleinbem.dev and the
      # mesh-only vhosts resolve to (see netbird/dns.tf).
      cache_entrypoint =
        assert lib.assertMsg (lib.length cacheGroup == 1) (
          "iac/data.nix: inventory.meshGroups.cache must name exactly one host"
          + " (got: [ ${lib.concatStringsSep " " cacheGroup} ])"
        );
        lib.head meshPeers.cache;
    };

    mesh_only_fqdns = meshOnlyFqdns;
  };

  referentialIntegrity = lib.assertMsg (unknownRefs == [ ]) (
    "iac/data.nix: inventory.meshGroups references host(s) absent from inventory.hosts: "
    + lib.concatStringsSep ", " unknownRefs
  );
in
assert referentialIntegrity;
{
  inherit personasJson inventoryJson;
}
