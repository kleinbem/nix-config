#!/usr/bin/env bash
# Compare each kleinbem-secrets/initrd/cryptroot_<host>.jwe with the binding
# inventory.nix asks for (lib/tang.nix: every other host's Tang server).
# Reads only the JWE headers (server URLs), never decrypts. Exit 1 on drift.
set -euo pipefail
secrets="${KLEINBEM_SECRETS:-../kleinbem-secrets}/initrd"
[ -d "$secrets" ] || {
  echo "skip: $secrets not found"
  exit 0
}

hdr() { # decode a compact JWE's protected header
  local h
  h=$(printf '%s' "$1" | cut -d. -f1 | tr '_-' '/+')
  while [ $((${#h} % 4)) -ne 0 ]; do h="$h="; done
  printf '%s' "$h" | base64 -d
}

rc=0
for f in "$secrets"/cryptroot_*.jwe; do
  host=$(basename "$f" .jwe)
  host=${host#cryptroot_}
  [ -d "hosts/$host" ] || continue
  have=$(hdr "$(cat "$f")" | jq -r '.clevis.sss.jwe[]?' | while read -r j; do hdr "$j" | jq -r '.clevis.tang.url // empty'; done | sort | tr '\n' ' ')
  want=$(bash scripts/tang-config.sh "$host" | jq -r '.pins.tang[].url' | sort | tr '\n' ' ')
  if [ "$have" = "$want" ]; then
    echo "✓ $host"
  else
    echo "✗ $host bound to: ${have:-nothing}"
    echo "    inventory wants: $want → just deployment::generate-jwe $host"
    rc=1
  fi
done
exit $rc
