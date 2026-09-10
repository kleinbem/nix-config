# Single source of truth → OpenTofu bridge.
#
# The `nix/infra` OpenTofu roots can't `import` Nix, so a handful of facts
# that live canonically in this repo (personas.nix + private contact data,
# inventory.nix) are projected to JSON here and consumed by those roots via
# `jsondecode(file(...))`:
#
#   iac/data.nix ──► nix/infra/personas.json   (personas.tf, cloudflare-dns.tf)
#              └───► nix/infra/inventory.json   (netbird/{inventory,groups}.tf)
#
# Regenerate the JSON with `nix/tools/gen-iac-data.sh` (was the ad-hoc
# `export-personas.sh` + a hand-maintained duplicate of the peer lists).
# The `iac-data` flake package builds both files; the `iac-data` flake check
# forces the schema + referential-integrity assertions below, and
# `nix/tools/check-iac-data.sh` guards the committed copies against drift.
{
  lib,
  inventory ? import ../inventory.nix,
  personas ? import ../personas.nix,
  # kleinbem-secrets/personas/contact.nix — plain Nix (private repo, not sops;
  # see that file's header). The flake passes
  # `inputs.nix-secrets + "/personas/contact.nix"`; empty = public-only eval
  # (personas.json then lacks the PII fields, same as the old script's
  # no-secrets fallback).
  contact ? { },
}:
let
  # personas.json — byte-for-byte the old `export-personas.sh` merge:
  # public role/auth layer ⊕ private contact layer, per persona. Consumers
  # read `.email` (domain split → primary_domain) and, when wired,
  # `.dkim_pubkey_b64`.
  personasJson = lib.mapAttrs (name: p: p // (contact.${name} or { })) personas;

  hostNames = lib.attrNames inventory.hosts;

  # NetBird mesh group membership. Canonical here (inventory.meshGroups);
  # was duplicated as `variable ... { default = [...] }` in
  # nix/infra/netbird/{groups,peers}.tf.
  meshGroups = inventory.meshGroups or { };
  groupNames = lib.attrNames meshGroups;

  unknownRefs = lib.concatMap (
    g: map (h: "${g}/${h}") (lib.filter (h: !(lib.elem h hostNames)) meshGroups.${g})
  ) groupNames;

  cacheGroup = meshGroups.cache or [ ];

  inventoryJson = {
    # Minimal host projection — only what the netbird root needs.
    hosts = lib.mapAttrs (_: h: {
      tags = h.tags or [ ];
      ip = h.ip or null;
      netbirdIp = h.netbirdIp or null;
      system = h.system or null;
      type = h.type or null;
    }) inventory.hosts;

    mesh = meshGroups // {
      # The one caddy/attic entrypoint peer that cache.kleinbem.dev and the
      # mesh-only vhosts resolve to (see netbird/dns.tf).
      cache_entrypoint =
        assert lib.assertMsg (lib.length cacheGroup == 1) (
          "iac/data.nix: inventory.meshGroups.cache must name exactly one host"
          + " (got: [ ${lib.concatStringsSep " " cacheGroup} ])"
        );
        lib.head cacheGroup;
    };
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
