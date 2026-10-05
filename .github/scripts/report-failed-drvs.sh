#!/usr/bin/env bash
# report-failed-drvs.sh <label> <marker-file>
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
set -uo pipefail

label=$1
marker=$2
summary=${GITHUB_STEP_SUMMARY:-/dev/stdout}
logdir=/nix/var/log/nix/drvs

echo "::group::disk usage at failure time"
df -h / /nix 2>/dev/null
echo "::endgroup::"

echo "### $label: failed derivations" >>"$summary"
found=0
while read -r log; do
  rel=${log#"$logdir"/}
  b=${rel/\//}
  b=${b%.bz2}
  d=/nix/store/$b
  [ -f "$d" ] || continue
  # shellcheck disable=SC2046 # one store path per output, no spaces
  nix-store --check-validity $(nix-store -q --outputs "$d") 2>/dev/null && continue
  found=1
  echo "- \`${b#*-}\`" >>"$summary"
  echo "::group::FAILED ${b#*-}"
  echo "--- failure lines (whole log, max 60) ---"
  bzcat "$log" | grep -E '^=== release|^Path: |not ok [0-9]|FAIL|[Ee]rror[: ]|Killed|No space left|out of memory|Segmentation fault' | head -n 60
  echo "--- last 80 lines ---"
  bzcat "$log" | tail -n 80
  echo "::endgroup::"
done < <(find "$logdir" -type f -name '*.bz2' -newer "$marker" 2>/dev/null)
[ "$found" -eq 1 ] || echo "- (no attempted-and-failed derivation found — eval failure, timeout, or runner loss; see the step log)" >>"$summary"
