#!/usr/bin/env bash
# Mint one Attic token with the CURRENT signing key (no rotation) and write it
# straight into sops. Like attic-rotate.sh, nothing lands on disk unencrypted
# or in a process listing.
#
#   attic-mint.sh <sops file> <key> <make-token args...>
#   attic-mint.sh infra/terraform.yaml attic_ci_pull_token --sub github-ci-pull --pull system
set -euo pipefail

[ $# -ge 3 ] || {
  echo "usage: $0 <sops file> <key> <make-token args...>" >&2
  exit 1
}
file=$1 key=$2
shift 2

S="${KLEINBEM_SECRETS:-../kleinbem-secrets}"
for f in nix/per-host/core-pi.yaml "$file"; do
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

ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$(sops -d --extract '["attic_server_token_rs256"]' "$S/nix/per-host/core-pi.yaml")
export ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64
atticadm=$(nix build --no-link --print-out-paths nixpkgs#attic-server)/bin/atticadm

"$atticadm" -f "$tmp/server.toml" make-token --validity 1y "$@" |
  tr -d '\n' | jq -Rs . | sops set --value-stdin "$S/$file" "[\"$key\"]"
unset ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64
echo "   ✓ $key → $file"
