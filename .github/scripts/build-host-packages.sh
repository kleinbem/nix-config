#!/usr/bin/env bash
# Build a host's packages but not its system: the assembly steps
# (scripts/heavy-drvs.sh) are left to the host, so CI never downloads the
# whole closure just to assemble it.
# Usage: build-host-packages.sh <host> [--push] [nix args for the eval...]
set -euo pipefail
host=$1
shift
push=false
if [ "${1:-}" = --push ]; then
  push=true
  shift
fi

attr=".#nixosConfigurations.$host.config.system.build.toplevel"
# always-allow-substitutes: as on the host, so cached allowSubstitutes = false
# drvs don't count as missing.
if ! out=$(nix build --no-link --dry-run --option always-allow-substitutes true "$attr" "$@" 2>&1); then
  echo "$out"
  exit 1
fi
classified=$(scripts/heavy-drvs.sh <<<"$out")
mapfile -t heavy < <(sed -n 's/^heavy //p' <<<"$classified")
echo "$host: ${#heavy[@]} packages to build, $(grep -c '^small ' <<<"$classified" || true) assembly steps left to the host"
[ "${#heavy[@]}" -gt 0 ] || exit 0

# Every heavy drv is a target: a cached intermediate can hide a requisite.
if outs=$(nix build --no-link --keep-going --print-out-paths -L "${heavy[@]/%/^*}"); then
  rc=0
else
  rc=1
  # Push what did build, so a retry only redoes the failures.
  outs=$(nix-store --query --outputs "${heavy[@]}" | while read -r p; do [ -e "$p" ] && echo "$p"; done || true)
fi
if $push && [ -n "$outs" ]; then
  mapfile -t paths <<<"$outs"
  attic push system "${paths[@]}"
fi
exit $rc
