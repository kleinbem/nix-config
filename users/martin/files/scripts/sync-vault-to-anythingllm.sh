#!/usr/bin/env bash
# Push new/changed Obsidian vault notes into AnythingLLM via its documented
# REST API (verified live against the instance's own /api/docs spec,
# 2026-09-20: POST /api/v1/document/upload/{folder} to ingest+embed, DELETE
# /api/v1/system/remove-documents to remove). AnythingLLM has no
# watched-folder ingestion, and re-uploading an unchanged file creates a
# duplicate (each upload gets a random suffix, not a content hash) — hence
# the mtime-keyed state file: only touch files that actually changed, and
# explicitly delete-then-reupload so the vector store never accumulates
# stale copies of an edited note.
set -euo pipefail

VAULT_PATH="$HOME/Documents/Notes"
STATE_FILE="$HOME/.local/state/anythingllm-vault-sync/state.json"
BASE_URL="${ANYTHINGLLM_BASE_URL:?ANYTHINGLLM_BASE_URL not set}"
API_KEY_FILE="${ANYTHINGLLM_API_KEY_FILE:-/run/secrets/anythingllm_api_key}"
WORKSPACE_SLUG="${ANYTHINGLLM_WORKSPACE_SLUG:-vault}"
FOLDER="obsidian-vault"

if [ ! -d "$VAULT_PATH" ]; then
  echo "anythingllm-vault-sync: no vault at $VAULT_PATH, skipping" >&2
  exit 0
fi

if [ ! -f "$API_KEY_FILE" ]; then
  echo "anythingllm-vault-sync: no API key at $API_KEY_FILE yet (bootstrap not done) — skipping" >&2
  exit 0
fi
API_KEY=$(cat "$API_KEY_FILE")

mkdir -p "$(dirname "$STATE_FILE")"
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"
state=$(cat "$STATE_FILE")
new_state="$state"

auth=(-H "Authorization: Bearer ${API_KEY}")

remove_document() {
  local location="$1"
  curl -fsS "${auth[@]}" -H "Content-Type: application/json" \
    -X DELETE "${BASE_URL}/api/v1/system/remove-documents" \
    -d "$(jq -nc --arg n "$location" '{names: [$n]}')" >/dev/null || true
}

added=0
updated=0
removed=0
declare -A seen

while IFS= read -r -d '' f; do
  rel="${f#"$VAULT_PATH"/}"
  seen["$rel"]=1
  mtime=$(stat -c %Y "$f")
  prev_mtime=$(jq -r --arg k "$rel" '.[$k].mtime // empty' <<<"$state")
  prev_loc=$(jq -r --arg k "$rel" '.[$k].location // empty' <<<"$state")

  [ "$prev_mtime" = "$mtime" ] && continue

  [ -n "$prev_loc" ] && remove_document "$prev_loc"

  resp=$(curl -fsS "${auth[@]}" \
    -F "file=@${f}" \
    -F "addToWorkspaces=${WORKSPACE_SLUG}" \
    "${BASE_URL}/api/v1/document/upload/${FOLDER}") || {
    echo "anythingllm-vault-sync: upload request failed for $rel" >&2
    continue
  }

  loc=$(jq -r '.documents[0].location // empty' <<<"$resp")
  if [ -z "$loc" ]; then
    echo "anythingllm-vault-sync: upload failed for $rel: $resp" >&2
    continue
  fi

  if [ -n "$prev_loc" ]; then
    updated=$((updated + 1))
  else
    added=$((added + 1))
  fi
  new_state=$(jq --arg k "$rel" --arg loc "$loc" --arg mt "$mtime" \
    '.[$k] = {location: $loc, mtime: ($mt | tonumber)}' <<<"$new_state")
done < <(find "$VAULT_PATH" -type f -name '*.md' \
  ! -path '*/.obsidian/*' ! -path '*/.trash/*' ! -name '*sync-conflict*' \
  -print0)

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if [ -z "${seen[$rel]:-}" ]; then
    loc=$(jq -r --arg k "$rel" '.[$k].location' <<<"$state")
    remove_document "$loc"
    new_state=$(jq --arg k "$rel" 'del(.[$k])' <<<"$new_state")
    removed=$((removed + 1))
  fi
done < <(jq -r 'keys[]' <<<"$state")

echo "$new_state" > "$STATE_FILE"
echo "anythingllm-vault-sync: +${added} ~${updated} -${removed}"
