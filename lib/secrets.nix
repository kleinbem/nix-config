# Per-container sops.secrets generator.
#
# hosts/*/secrets.nix were hand-duplicating blocks like:
#   authentik_secret_key = { sopsFile = "${inputs.kleinbem-secrets}/nix/per-container/authentik.yaml"; };
#   authentik_postgres_password = { sopsFile = "${inputs.kleinbem-secrets}/nix/per-container/authentik.yaml"; };
#   ...
# one entry per secret, only the suffix changing — core-pi/secrets.nix alone
# had 17 of these across authelia/kleinbem-auth/authentik. mkPerContainerSecrets
# generates the same attrset from a plain list of suffixes.
#
# Two real naming conventions exist in kleinbem-secrets' per-container YAML
# files (confirmed 2026-09-21 against their actual plaintext keys):
#   - authelia.yaml / authentik.yaml: the YAML key IS the full attr name
#     (e.g. "authentik_secret_key") — sops-nix's default `key` (= the attr
#     name) already matches, so `fullKey = true` (the default) omits `key`.
#   - kleinbem-auth.yaml: the YAML key is the BARE suffix (e.g.
#     "better_auth_secret", not "kleinbem_auth_better_auth_secret") — pass
#     `fullKey = false` so each generated entry gets `key = suffix;`.
{ lib, inputs }:
{
  container,
  keys,
  # attr name prefix — defaults to `container` with hyphens turned into
  # underscores (e.g. "kleinbem-auth" -> "kleinbem_auth"), since Nix/sops-nix
  # attr names don't take hyphens the same way file/container names do.
  prefix ? lib.replaceStrings [ "-" ] [ "_" ] container,
  fullKey ? true,
}:
lib.listToAttrs (
  map (
    suffix:
    lib.nameValuePair "${prefix}_${suffix}" (
      {
        sopsFile = "${inputs.kleinbem-secrets}/nix/per-container/${container}.yaml";
      }
      // lib.optionalAttrs (!fullKey) { key = suffix; }
    )
  ) keys
)
