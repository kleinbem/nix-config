# Persona library — helpers for consuming personas.nix.
#
# Pattern:
#   let personas = import ../lib/personas.nix { inherit lib; };
#   in personas.author "michael"          → "Michael Gruber <michael@kleinbem.dev>"
#      personas.all                        → attribute set of all personas
#      personas.allowedSigners persona-keys → string for ~/.ssh/allowed_signers

{ lib }:
let
  manifest = import ../personas.nix;

  # Render a single persona's `Author:` string in the form git/jj expect.
  author = name:
    let p = manifest.${name}; in
    "${p.full-name} <${p.email}>";

  # Render the allowed_signers contents from the manifest + a key map.
  # personaKeys is { michael = "ssh-ed25519 AAAA..."; thomas = "..."; }
  # — typically built from the .pub files at deploy time.
  allowedSigners = personaKeys:
    let
      lines = lib.mapAttrsToList
        (name: persona:
          let key = personaKeys.${name} or null; in
          lib.optionalString (key != null) "${persona.email} ${key}"
        )
        manifest;
    in
    lib.concatStringsSep "\n" (lib.filter (s: s != "") lines) + "\n";

  # All persona names (for iteration in modules / containers / etc.).
  names = lib.attrNames manifest;

  # Validate that every persona attribute set has the required fields.
  # Use at evaluation time to fail fast if someone adds an incomplete entry.
  assertComplete =
    let
      required = [ "full-name" "origin" "timezone" "email" "github-handle" "tool" "signing-key" ];
      check = name: persona:
        let missing = lib.filter (k: !(persona ? ${k})) required; in
        lib.assertMsg (missing == [])
          "persona '${name}' is missing required field(s): ${lib.concatStringsSep ", " missing}";
    in
    builtins.all (n: check n manifest.${n}) names;
in
{
  inherit author allowedSigners names assertComplete;
  all = manifest;
}
