#!/usr/bin/env bash
# Usage: lock-failure-report.sh <eval log> <flake.lock before the update>
# Markdown report of why the nightly lock update failed. For a broken package it
# adds the derivation chain and a ready kleinbem/nix-detour-fleet entry pinned to
# the nixpkgs the fleet runs now (the lock before the update).
set -euo pipefail
log=$1 lock_before=$2

check=$(grep -m1 '^FAILED ' "$log" | cut -d' ' -f2- || true)
echo "The nightly lock update failed validation${check:+ at \`$check\`}."
echo
echo '```'
grep -E '^\s*error:|Failed assertions|^\s+- ' "$log" | grep -vE '^\s+[0-9]+\|' | grep -v '^\s*- Nixpkgs import\|^\s*- NixOS:\|^\s*- nix-\*' | head -12
echo '```'

broken=$(grep -oE "Refusing to evaluate package '[^']+'" "$log" | head -1 | cut -d"'" -f2 || true)
[[ -n $broken ]] || exit 0

node=$(jq -r '.nodes.root.inputs.nixpkgs' "$lock_before")
rev=$(jq -r --arg n "$node" '.nodes[$n].locked.rev' "$lock_before")
narHash=$(jq -r --arg n "$node" '.nodes[$n].locked.narHash' "$lock_before")

echo
echo "\`$broken\` is marked broken. The chain from the failing configuration down to it:"
echo
echo '```'
grep -oE "while evaluating (derivation '[^']+'|the option \`[^']+')" "$log" | sed 's/^while evaluating //' | head -20
echo '```'
echo
echo "Hold the package the fleet uses (the lowest top-level package in the chain, not \`$broken\` itself) in kleinbem/nix-detour-fleet \`held-packages.json\`:"
echo
echo '```json'
jq -n --arg rev "$rev" --arg narHash "$narHash" --arg broken "$broken" --arg since "$(date -u +%F)" '{
  "<attribute>": {
    from: { rev: $rev, narHash: $narHash },
    since: $since,
    releaseWhen: "<nixpkgs attribute of the broken package, e.g. python3Packages.x>",
    reason: ("Needs " + $broken + ", marked broken in nixos-unstable; <what failed>."),
    link: "<upstream fix PR or issue>"
  }
}'
echo '```'
