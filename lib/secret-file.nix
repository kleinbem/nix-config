# secretFile "nix/shared.yaml" → a store path holding only that one file.
# Interpolating "${inputs.kleinbem-secrets}/…" would drag the whole secrets
# repo into every closure as string context.
# Only for encrypted files; plaintext keys live on the host (host-secrets.nix).
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
