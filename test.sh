set -o pipefail
# Construct build arguments.
# --eval-workers 2: cap parallel eval-jobs forks. Default = nproc,
# which on the 7 GiB hosted runner has been OOM-killing the runner
# before the build step produces any output (visible as the
# "hosted runner lost communication" error). Same issue hits meta's
# build-all; this is the conservative first-pass fix.
# Check enumeration via `nix eval` + attrNames, NOT `nix flake show`:
# flake show evaluates every output of every system just to list
# names, and on the CI (Determinate) Nix it emitted `"checks": null`
# instead of failing — with stderr discarded, CI_CHECKS was silently
# EMPTY and this job built zero checks for months (run 29467089940
# and earlier). Hence also the emptiness guard: an empty list is
# always an enumeration bug, never a real state, so fail loud.
#
# Exclusions:
# - VM-based NixOS tests (caddy/code-server/mobile-link/recovery) run
#   in the dedicated vm-tests.yaml workflow; they remain in .#checks
#   for local runs.
# - host-* checks: hosts are targeted EXPLICITLY below (hass-pi +
#   core-pi hardcoded native, nixos-nvme in its own best-effort step
#   because its ~8.6 GiB eval needs swap + isolation; Orin/routers
#   deliberately never build in CI — jetpack/bespoke kernels).
#   Enumerating them here would re-add those giant builds blocking.
# What this restores is the real checks — pre-commit-check and the
# flake-lock-no-file-url reproducibility guard, which must gate
# every PR.
SYSTEM="${{ matrix.system }}"
mapfile -t CI_CHECKS < <(nix eval ".#checks.$SYSTEM" \
    --apply builtins.attrNames --json $NIX_OVERRIDES \
  | jq -r '.[] | select(test("(caddy|code-server|mobile-link|recovery)-test|^host-") | not)')
if [ "${#CI_CHECKS[@]}" -eq 0 ]; then
  echo "::error::.#checks.$SYSTEM enumeration came back empty — enumeration is broken (it can never legitimately be empty)."
  exit 1
fi
echo "CI checks to build: ${CI_CHECKS[*]}"

COMMON=(
  "--no-nom"
  "--skip-cached"
  "--eval-workers" "2"
  "--systems" "$SYSTEM"
  # Retry failed builds twice — the Attic push rides NetBird, so a
  # transient network/SSH hiccup retries instead of failing the target.
  "--retries" "2"
)
# If pushing to cache, tell nix-fast-build to use Attic directly.
if [ "${{ steps.cache.outputs.push_cache }}" == "true" ]; then
  COMMON+=("--attic-cache" "system")
fi

# IMPORTANT: nix-fast-build's `--flake` is SINGLE-VALUED (argparse
# store — the LAST one wins). Passing multiple `--flake` silently
# builds only the last target, which is why the cache was badly
# under-populated (only `.#devShells` ever built). So we invoke
# nix-fast-build ONCE PER target.
#
# Build only what hosts actually DEPLOY: their system toplevels (native
# arch) + devShells + non-VM checks. We deliberately do NOT build
# `.#packages` — it exposes cross-arch install IMAGES (e.g.
# router-1-image, an aarch64 image that gets cross-built on the x86_64
# runner) and standalone packages that no host deploys. Everything a
# host actually uses is already in its toplevel closure, so building
# toplevels caches it natively without the cross-build waste.
#
# The bare `.#nixosConfigurations` does NOT materialize host toplevels,
# so name them explicitly. Each host builds on its native-arch runner
# (matrix), so no emulation. RPi5 hosts carry the custom linux-rpi
# kernel (absent from cache.nixos.org). Excluded: routers (bespoke
# Banana Pi R4 kernel) — add once they're confirmed to build in CI.
TARGETS=()
for c in "${CI_CHECKS[@]}"; do
  TARGETS+=(".#checks.$SYSTEM.$c")
done
# devShells are for DEVELOPMENT on the x86_64 workstation. Edge
# (aarch64) hosts are headless and never run `nix develop`, so don't
# waste a runner building them there.
if [ "$SYSTEM" = "x86_64-linux" ]; then
  TARGETS+=( 
    ".#devShells" 
    ".#nixosConfigurations.nasbook.config.system.build.toplevel"
  )
fi
if [ "$SYSTEM" = "aarch64-linux" ]; then
  TARGETS+=(
    ".#nixosConfigurations.hass-pi.config.system.build.toplevel"
    ".#nixosConfigurations.core-pi.config.system.build.toplevel"
    # Orin-nano uses Jetpack kernels which cause massive issues in CI (unfree/disk space).
    # But we can still cache 99% of its userspace by building its path and etc trees!
    ".#nixosConfigurations.orin-nano.config.system.build.etc"
    ".#nixosConfigurations.orin-nano.config.system.path"
  )
fi

rc=0
for t in "${TARGETS[@]}"; do
  echo "::group::nix-fast-build $t"
  nix run github:Mic92/nix-fast-build -- "${COMMON[@]}" --flake "$t" $NIX_OVERRIDES || rc=1
  echo "::endgroup::"
done
exit $rc

