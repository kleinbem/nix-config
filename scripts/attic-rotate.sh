#!/usr/bin/env bash
# Rotate the Attic token signing key and re-issue every token, least privilege
# per consumer. Every token signed with the old key (including the admin
# tokens that sat in plaintext in ~/.config/attic/config.toml) stops working
# once core-pi runs with the new key.
#
# Everything is generated locally and written straight into sops via stdin:
# nothing lands on disk unencrypted or in a process listing.
#
#   attic_server_token_rs256  nix/per-host/core-pi.yaml     new signing key
#   attic_pull_token          nix/shared.yaml               sub fleet-pull: pull system
#   attic_push_token          nix/per-host/orin-nano.yaml   sub orin-nano: pull+push system
#   attic_ci_push_token       infra/terraform.yaml          sub github-ci: pull+push system
#   attic_admin_token         nix/per-host/nixos-nvme.yaml  sub admin: everything; only via `just nixos::attic`
#
# Afterwards: commit kleinbem-secrets, bump it in nix-config, deploy core-pi
# first, then the other hosts, run nix's tools/tf-apply.sh (GitHub secret),
# then `just nixos::attic cache configure system --private`.
set -euo pipefail

S="${KLEINBEM_SECRETS:-../kleinbem-secrets}"
for f in nix/per-host/core-pi.yaml nix/shared.yaml nix/per-host/orin-nano.yaml infra/terraform.yaml nix/per-host/nixos-nvme.yaml; do
  [ -f "$S/$f" ] || {
    echo "missing $S/$f" >&2
    exit 1
  }
done

tmp=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}")
trap 'rm -rf "$tmp"' EXIT
# atticadm only needs a syntactically valid server config to sign tokens.
cat >"$tmp/server.toml" <<'TOML'
listen = "127.0.0.1:0"
[database]
url = "sqlite::memory:"
[storage]
type = "local"
path = "/nonexistent"
[chunking]
nar-size-threshold = 65536
min-size = 16384
avg-size = 65536
max-size = 262144
TOML

# Same format as the attic docs: PKCS#1 PEM, base64.
ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$(openssl genrsa -traditional 4096 2>/dev/null | base64 -w0)
export ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64
atticadm=$(nix build --no-link --print-out-paths nixpkgs#attic-server)/bin/atticadm

mint() { "$atticadm" -f "$tmp/server.toml" make-token --validity 1y "$@"; }
put() { # put <file> <key>; value on stdin
  tr -d '\n' | jq -Rs . | sops set --value-stdin "$S/$1" "[\"$2\"]"
  echo "   ✓ $2 → $1"
}

echo "🔑 New signing key generated; writing it and the new tokens to sops (YubiKey prompts follow)..."
printf '%s' "$ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64" | put nix/per-host/core-pi.yaml attic_server_token_rs256
mint --sub fleet-pull --pull system | put nix/shared.yaml attic_pull_token
mint --sub orin-nano --pull system --push system | put nix/per-host/orin-nano.yaml attic_push_token
mint --sub github-ci --pull system --push system | put infra/terraform.yaml attic_ci_push_token
mint --sub admin --pull '*' --push '*' --delete '*' --create-cache '*' --configure-cache '*' \
  --configure-cache-retention '*' --destroy-cache '*' | put nix/per-host/nixos-nvme.yaml attic_admin_token
unset ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64

cat <<'NEXT'

✅ Done. Old tokens die when core-pi restarts Attic with the new key. Next:
   1. Commit kleinbem-secrets; bump it in nix-config (nix flake update kleinbem-secrets).
   2. Deploy core-pi, then the other hosts (new pull token).
   3. nix: tools/tf-apply.sh  (ATTIC_PUSH_TOKEN for CI)
   4. just nixos::attic cache configure system --private
   5. rm ~/.config/attic/config.toml   (old admin tokens, now dead)
NEXT
