# Projects repo-canonical facts (personas.nix ⊕ private contact data,
# inventory.nix) to the JSON the `nix/infra` OpenTofu roots consume. See
# iac/data.nix for the full rationale.
#
#   nix build .#iac-data     → result/{personas.json,inventory.json}
#   nix flake check          → checks.iac-data forces the schema +
#                              referential-integrity assertions
#
# Both files are `jq -S` canonical (sorted keys, 2-space) so the copies in
# nix/infra diff cleanly. nix/tools/gen-iac-data.sh copies them into place;
# nix/tools/check-iac-data.sh drift-guards the committed copies.
{ inputs, ... }:
{
  perSystem =
    {
      config,
      lib,
      system,
      ...
    }:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};

      # kleinbem-secrets checkout (flake input, historically named
      # "nix-secrets"). personas/contact.nix is plain Nix — import directly.
      contactFile = inputs.nix-secrets + "/personas/contact.nix";
      contact = if builtins.pathExists contactFile then import contactFile else { };

      data = import ../../iac/data.nix { inherit lib contact; };

      # One formatter for every producer/consumer of these files.
      mkJson =
        name: value:
        pkgs.runCommand name {
          json = builtins.toJSON value;
          passAsFile = [ "json" ];
          nativeBuildInputs = [ pkgs.jq ];
        } ''jq -S . "$jsonPath" > "$out"'';

      personasJson = mkJson "personas.json" data.personasJson;
      inventoryJson = mkJson "inventory.json" data.inventoryJson;

      # Persona schema + email/matrix/signing-key uniqueness (throws on fail).
      personaLib = import ../../lib/personas.nix { inherit lib contact; };
    in
    {
      packages.iac-data = pkgs.runCommand "iac-data" { } ''
        mkdir -p "$out"
        cp ${personasJson} "$out/personas.json"
        cp ${inventoryJson} "$out/inventory.json"
      '';

      checks.iac-data =
        pkgs.runCommand "check-iac-data"
          {
            # Eval-forced: bad persona schema / dup identity throws here;
            # iac/data.nix's meshGroups assertions are forced via packages.
            personasValid = personaLib.assertValid;
          }
          ''
            [ "$personasValid" = "1" ] || {
              echo "lib/personas.nix assertValid returned false" >&2; exit 1;
            }
            test -s ${config.packages.iac-data}/personas.json
            test -s ${config.packages.iac-data}/inventory.json
            touch "$out"
          '';
    };
}
