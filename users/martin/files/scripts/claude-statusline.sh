#!/usr/bin/env bash
# Claude Code status line: where the session works, its jj change, model and
# context use. Reads the session JSON on stdin, prints one line.
input=$(cat)

dir=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")
model=$(jq -r '.model.display_name // empty' <<<"$input")
ctx=$(jq -r '.context_window.used_percentage // empty | floor? // empty' <<<"$input")

# <repo>.ws/<name> shows as repo:name, so parallel sessions are told apart.
where=${dir/#$HOME/\~}
parent=$(basename "$(dirname "$dir")")
if [[ $parent == *.ws ]]; then
  where="${parent%.ws}:$(basename "$dir")"
elif [[ -n $dir ]]; then
  where=$(basename "$dir")
fi

# --ignore-working-copy: a status line must never snapshot (and sign) @.
change=""
if [[ -n $dir ]]; then
  change=$(jj --ignore-working-copy --color never -R "$dir" log -r @ --no-graph \
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
