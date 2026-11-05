#!/usr/bin/env bash
# Claude Code status line: where the session works, its jj change, model and
# context use. Reads the session JSON on stdin, prints one line.
input=$(cat)

dir=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")
model=$(jq -r '.model.display_name // empty' <<<"$input")
ctx=$(jq -r '.context_window.used_percentage // empty | floor? // empty' <<<"$input")

# <repo>.ws/<name> (or any dir below it) shows as repo:name, so parallel
# sessions are told apart; otherwise the dir's own name.
where=""
d=$dir
while [[ -n $d && $d != / ]]; do
  parent=$(dirname "$d")
  if [[ $(basename "$parent") == *.ws ]]; then
    where="$(basename "$parent" .ws):$(basename "$d")"
    break
  fi
  d=$parent
done
[[ -z $where && -n $dir ]] && where=$(basename "$dir")

# --ignore-working-copy: a status line must never snapshot (and sign) @.
change=""
if [[ -n $dir ]]; then
  # jj finds the repo root from any subdirectory itself; -R would not.
  change=$(cd "$dir" 2>/dev/null &&
    jj --ignore-working-copy --color never log -r @ --no-graph \
      -T 'change_id.shortest(8) ++ if(empty, " empty", "") ++ if(conflict, " conflict", "")' \
      2>/dev/null || true)
fi

parts=("$where")
[[ -n $change ]] && parts+=("@$change")
[[ -n $model ]] && parts+=("$model")
[[ -n $ctx ]] && parts+=("ctx ${ctx}%")

out=""
for p in "${parts[@]}"; do
  out+="${out:+ · }$p"
done
printf '%s\n' "$out"
