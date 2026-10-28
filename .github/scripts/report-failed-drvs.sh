#!/usr/bin/env bash
# report-failed-drvs.sh <label> <marker-file> [attic-cache]
#
# Root-cause report for a failed best-effort nix-fast-build step. nix-fast-
# build keeps only the last 10k log lines per target, so on big closures the
# derivation that actually broke (often early) scrolls out and only "N
# dependencies failed" survives.
#
# Every derivation built since <marker-file> was touched (create it at the
# start of the step) has a fresh log under /nix/var/log/nix/drvs; one whose
# outputs aren't valid was attempted and failed. For each, print the
# failure-looking lines from its whole log plus its tail, and list it in the
# step summary. Scoping to logs newer than the marker (not "has a log, output
# missing") avoids flagging stale logs whose outputs were later GC'd.
#
# With [attic-cache], the derivations that DID build are pushed there.
# nix-fast-build only pushes when the whole target succeeds, so one broken
# package otherwise throws away hours of finished builds (2026-10-28: three
# nvme runs built nearly the whole closure around gimp3-mcp, pushed nothing).
#
# The first failure (derivation + its first failure line, else the log's last
# line) goes to $GITHUB_OUTPUT as `cause`, for the ntfy alert.
set -uo pipefail

label=$1
marker=$2
cache=${3:-}
summary=${GITHUB_STEP_SUMMARY:-/dev/stdout}
logdir=/nix/var/log/nix/drvs

echo "::group::disk usage at failure time"
df -h / /nix 2>/dev/null
echo "::endgroup::"

echo "### $label: failed derivations" >>"$summary"
found=0
cause=""
built=()
while read -r log; do
  rel=${log#"$logdir"/}
  b=${rel/\//}
  b=${b%.bz2}
  d=/nix/store/$b
  [ -f "$d" ] || continue
  outs=$(nix-store -q --outputs "$d")
  # shellcheck disable=SC2086 # one store path per output, no spaces
  if nix-store --check-validity $outs 2>/dev/null; then
    # shellcheck disable=SC2206
    built+=($outs)
    continue
  fi
  found=1
  if [ -z "$cause" ]; then
    line=$(bzcat "$log" | grep -aE '[Ee]rror[: ]|FAIL|not satisfied|Killed|No space left|out of memory|Segmentation fault' | head -n 1)
    [ -n "$line" ] || line=$(bzcat "$log" | grep -av '^\s*$' | tail -n 1)
    cause="${b#*-}: $(echo "$line" | tr -s ' \t' ' ' | sed 's/^ //' | cut -c1-200)"
  fi
  echo "- \`${b#*-}\`" >>"$summary"
  echo "::group::FAILED ${b#*-}"
  echo "--- failure lines (whole log, max 60) ---"
  bzcat "$log" | grep -aE '^=== release|^Path: |not ok [0-9]|FAIL|[Ee]rror[: ]|Killed|No space left|out of memory|Segmentation fault' | head -n 60
  echo "--- last 80 lines ---"
  bzcat "$log" | tail -n 80
  echo "::endgroup::"
done < <(find "$logdir" -type f -name '*.bz2' -newer "$marker" 2>/dev/null)
[ "$found" -eq 1 ] || echo "- (no attempted-and-failed derivation found — eval failure, timeout, or runner loss; see the step log)" >>"$summary"
[ -n "${GITHUB_OUTPUT:-}" ] && [ -n "$cause" ] && echo "cause=$cause" >>"$GITHUB_OUTPUT"

if [ -n "$cache" ] && [ "${#built[@]}" -gt 0 ]; then
  echo "::group::pushing ${#built[@]} outputs that did build to Attic ($cache)"
  # Best effort: a failed push must not change the step's outcome.
  printf '%s\n' "${built[@]}" | xargs attic push "$cache" ||
    echo "::warning::attic push of the partial build failed"
  echo "::endgroup::"
  echo "Pushed ${#built[@]} outputs that built to Attic despite the failure." >>"$summary"
fi
