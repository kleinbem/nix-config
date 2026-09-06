#!/usr/bin/env bash
# Compare the Vaultwarden version the fleet currently ships (whatever the
# pinned nixpkgs in ./flake.lock packages) against the latest upstream GitHub
# release, and shout if we're behind.
#
# Why this exists separately from the daily `nix flake update` PR (maintain.yml):
# that job bumps nixpkgs wholesale and treats a Vaultwarden security release
# like any other churn — no urgency signal, and if `main` is un-mergeable the
# bump silently stalls. Vaultwarden is an internet-facing credential store, so
# it gets its own nag. This script does NOT bump anything; nixpkgs owns that.
#
# Exit 0 always (a drift still exits 0 — the emitted GH issue is the signal, a
# red workflow badge is not). Prints a one-line verdict to stdout; writes a
# richer summary to $GITHUB_STEP_SUMMARY when running under Actions.
#
# Usage:  ./scripts/check-vaultwarden-version.sh
# Deps:   bash, curl, jq, nix (with flakes)
set -euo pipefail

cd "$(dirname "$0")/.."

REPO_SLUG="dani-garcia/vaultwarden"

log() { echo -e "\033[0;32m[INFO]\033[0m  $*" >&2; }
err() {
  echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
  exit 1
}

command -v jq >/dev/null || err "jq not found"
command -v nix >/dev/null || err "nix not found"

# ── 1. What we ship: vaultwarden.version at the pinned nixpkgs rev ────────────
NIXPKGS_REV=$(jq -r '.nodes.nixpkgs.locked.rev' flake.lock)
[[ -n $NIXPKGS_REV && $NIXPKGS_REV != "null" ]] || err "no .nodes.nixpkgs.locked.rev in flake.lock"
log "pinned nixpkgs: $NIXPKGS_REV"

CURRENT=$(nix eval --raw "github:NixOS/nixpkgs/${NIXPKGS_REV}#vaultwarden.version" 2>/dev/null) ||
  err "could not eval vaultwarden.version at $NIXPKGS_REV"
log "shipped Vaultwarden: $CURRENT"

# ── 2. Latest upstream release ──────────────────────────────────────────────
GH_API=(-fsSL -H "Accept: application/vnd.github+json")
[[ -n ${GH_TOKEN:-} ]] && GH_API+=(-H "Authorization: Bearer ${GH_TOKEN}")

REL_JSON=$(curl "${GH_API[@]}" "https://api.github.com/repos/${REPO_SLUG}/releases/latest") ||
  err "GitHub releases API call failed"
LATEST=$(jq -r '.tag_name' <<<"$REL_JSON")
[[ -n $LATEST && $LATEST != "null" ]] || err "could not read .tag_name"
REL_URL=$(jq -r '.html_url' <<<"$REL_JSON")
REL_BODY=$(jq -r '.body // ""' <<<"$REL_JSON")
log "latest upstream:    $LATEST"

# ── 3. Verdict ─────────────────────────────────────────────────────────────
emit_summary() { [[ -n ${GITHUB_STEP_SUMMARY:-} ]] && echo -e "$1" >>"$GITHUB_STEP_SUMMARY"; }

if [[ $CURRENT == "$LATEST" ]]; then
  echo "OK: Vaultwarden $CURRENT is current."
  emit_summary "## ✅ Vaultwarden up to date\n\nShipping \`$CURRENT\` — matches upstream latest."
  exit 0
fi

# Heuristic: does the release note itself say "security"?
SECURITY_FLAG="no"
grep -qiE 'securit|advisor|CVE-|vulnerab' <<<"$REL_BODY" && SECURITY_FLAG="yes"

echo "DRIFT: shipping $CURRENT, upstream latest is $LATEST (security-worded: $SECURITY_FLAG)"
emit_summary "## ⚠️ Vaultwarden is behind upstream\n"
emit_summary "| | |"
emit_summary "|---|---|"
emit_summary "| Shipping (pinned nixpkgs) | \`$CURRENT\` |"
emit_summary "| Upstream latest | [\`$LATEST\`]($REL_URL) |"
emit_summary "| Release note mentions security | **$SECURITY_FLAG** |"
emit_summary "\nThe daily \`Maintain Flake\` PR bumps nixpkgs; if this persists, \`main\` isn't merging or nixpkgs hasn't packaged it yet."

# Machine-readable outputs for the workflow (issue creation).
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  {
    echo "drift=true"
    echo "current=$CURRENT"
    echo "latest=$LATEST"
    echo "security=$SECURITY_FLAG"
    echo "release_url=$REL_URL"
  } >>"$GITHUB_OUTPUT"
fi
exit 0
