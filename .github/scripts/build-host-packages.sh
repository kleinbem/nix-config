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
# A path Nix can neither fetch nor build; the dry-run still exits 0.
if grep -qE "do.?n.?t know how to build" <<<"$out"; then
  echo "$out"
  echo "::error::$host: the dry-run names paths that are neither cached nor buildable"
  exit 1
fi
classified=$(scripts/heavy-drvs.sh <<<"$out")
mapfile -t heavy < <(sed -n 's/^heavy //p' <<<"$classified")
echo "$host: ${#heavy[@]} packages to build, $(grep -c '^small ' <<<"$classified" || true) assembly steps left to the host"
# Two retries, as nix-fast-build had: fetches and the Attic push ride NetBird.
retry() {
  local i
  for i in 1 2 3; do
    "$@" && return 0
    if [ "$i" -lt 3 ]; then
      echo "attempt $i failed: $1; retrying in $((i * 5))s" >&2
      sleep $((i * 5))
    fi
  done
  return 1
}

rc=0
if [ "${#heavy[@]}" -gt 0 ]; then
  # Every heavy drv is a target: a cached intermediate can hide a requisite.
  retry nix build --no-link --keep-going -L "${heavy[@]/%/^*}" || rc=1
fi

if $push; then
  # Push every output of the host's closure present here, not only what this
  # script built: an earlier step may have built one of its packages without
  # pushing it, and the dry-run counts that as present. Attic skips what it
  # already has; assembly outputs are never built here, so never pushed.
  drv=$(nix path-info --derivation "$attr" "$@")
  mapfile -t paths < <(nix-store --query --requisites "$drv" | grep '\.drv$' |
    xargs nix-store --query --outputs | while read -r p; do [ -e "$p" ] && echo "$p"; done)
  [ "${#paths[@]}" -eq 0 ] || retry attic push system "${paths[@]}"
fi
exit $rc
