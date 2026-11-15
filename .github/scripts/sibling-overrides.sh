#!/usr/bin/env bash
# Usage: sibling-overrides.sh resolve            -> "repo=sha ..." for each sibling's main
#        sibling-overrides.sh canonical "<revs>" -> the same revs, validated, nothing else kept
#        sibling-overrides.sh flags "<revs>"     -> the --override-input flags for those revs
# CI floats the siblings to main, but resolves main once per build-all run:
# promote must evaluate the same revs build-all built, or a sibling merge in
# between changes the store paths and promote finds them uncached.
set -euo pipefail

SIBLINGS=(nix-devshells nix-hardware nix-packages nix-presets nix-templates)

resolve() {
  local out=() r sha
  for r in "${SIBLINGS[@]}"; do
    sha=$(git ls-remote "https://github.com/kleinbem/$r" refs/heads/main | cut -f1)
    out+=("$r=$sha")
  done
  echo "${out[*]}"
}

# github:kleinbem/<repo>/<sha> for one sibling out of "repo=sha ..."
pin() {
  local pair sha=""
  for pair in $2; do
    [[ ${pair%%=*} == "$1" ]] && sha=${pair#*=}
  done
  if ! [[ $sha =~ ^[0-9a-f]{40}$ ]]; then
    echo "sibling-overrides: no full commit SHA for $1 in '$2'" >&2
    exit 1
  fi
  echo "github:kleinbem/$1/$sha"
}

canonical() {
  local out=() r
  for r in "${SIBLINGS[@]}"; do
    out+=("$r=$(pin "$r" "$1" | sed 's|.*/||')")
  done
  echo "${out[*]}"
}

flags() {
  local d h p s t
  d=$(pin nix-devshells "$1")
  h=$(pin nix-hardware "$1")
  p=$(pin nix-packages "$1")
  s=$(pin nix-presets "$1")
  t=$(pin nix-templates "$1")
  echo "--override-input kleinbem-secrets /tmp/dummy-secrets" \
    "--override-input nix-devshells $d" \
    "--override-input nix-hardware $h" \
    "--override-input nix-hardware/nix-devshells $d" \
    "--override-input nix-packages $p" \
    "--override-input nix-packages/nix-devshells $d" \
    "--override-input nix-presets $s" \
    "--override-input nix-presets/nix-devshells $d" \
    "--override-input nix-presets/nix-packages $p" \
    "--override-input nix-presets/nix-packages/nix-devshells $d" \
    "--override-input nix-templates $t" \
    "--override-input nix-templates/nix-devshells $d"
}

case "${1:-}" in
resolve) resolve ;;
canonical) canonical "${2:-}" ;;
flags) flags "${2:-}" ;;
*)
  echo "usage: $0 resolve | canonical '<repo=sha ...>' | flags '<repo=sha ...>'" >&2
  exit 2
  ;;
esac
