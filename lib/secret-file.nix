# secretFile "nix/shared.yaml" → a store path holding only that one file.
#
# Interpolating "${inputs.kleinbem-secrets}/…" gives the string the whole
# repo as context, so every system closure (and every Attic push) carried
# the entire secrets repo. builtins.path copies just the named file.
#
# Only for encrypted files (sops YAML, tang JWE). Plaintext keys never go
# through here: they live on the host itself, see modules/nixos/host-secrets.nix.
{ inputs }:
rel:
let
  src = inputs.kleinbem-secrets + "/${rel}";
in
if builtins.pathExists src then
  builtins.path {
    path = src;
    name = baseNameOf rel;
  }
else
  # CI's dummy secrets tree lacks some files (persona YAMLs). sops-nix with
  # validateSopsFiles = false accepts a missing path; builtins.path would
  # abort evaluation instead.
  "/run/missing-secret/${rel}"
