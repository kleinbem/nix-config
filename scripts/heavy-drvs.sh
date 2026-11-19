#!/usr/bin/env bash
# Sort the "will be built" list of a `nix build --dry-run` (read on stdin) into
# real packages and system-assembly steps. Prints `heavy <drv>` or
# `small <drv>` per line. Assembly steps (etc, units, activation, the toplevel,
# preferLocalBuild) reference the whole closure but build in seconds, so CI
# leaves them to the host; anything heavy must come from the cache.
# Used by build-nvme.yaml, `just dev::attic-coverage` and the auto-upgrade gate.
set -euo pipefail

mapfile -t built < <(sed -n '/will be built:/,/will be fetched\|^$/p' | grep -oE '/nix/store/[^ ]+\.drv' || true)
[ "${#built[@]}" -gt 0 ] || exit 0

prefer_local=$(nix derivation show "${built[@]}" 2>/dev/null |
  jq -r '(.derivations // .) | to_entries[]
    | select(.value.env.preferLocalBuild == "1" or .value.structuredAttrs.preferLocalBuild == true)
    | .key | sub(".*/"; "")')
assembly='^(nixos-system-.*|activate|dry-activate|etc|system-units|user-units|unit-.*|manifest(-for-users)?\.json|boot\.json|append-initrd-secrets|check-.*)$'

for drv in "${built[@]}"; do
  base=${drv##*/}
  name=${base:33}
  name=${name%.drv}
  if [[ $name =~ $assembly ]] || grep -qxF "$base" <<<"$prefer_local"; then
    echo "small $drv"
  else
    echo "heavy $drv"
  fi
done
