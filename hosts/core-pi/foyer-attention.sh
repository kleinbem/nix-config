# shellcheck shell=bash
# Writes Foyer's attention feed ($FEED_DIR/attention.json) from public GitHub
# data, without a token: open pull requests of $GITHUB_USER that need a look,
# and failing checks on the default branch of $WATCH_REPOS.
api="${GITHUB_API:-https://api.github.com}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

get() {
  curl --silent --show-error --fail --max-time 20 \
    -H "Accept: application/vnd.github+json" -H "User-Agent: foyer-attention" "$1"
}

# search <file> <severity> <title prefix> <query>
search() {
  get "$api/search/issues?per_page=20&sort=updated&q=is:pr+is:open+$4" |
    jq --arg severity "$2" --arg prefix "$3" '
      # A search that timed out on the GitHub side lists only part of the matches.
      if .incomplete_results then error("incomplete search results") else . end
      | [.items[] | {
          id: "\($prefix):\(.html_url)",
          title: "\($prefix): \(.title)",
          url: .html_url,
          source: "\(.repository_url | sub(".*/repos/"; ""))#\(.number)",
          severity: $severity,
          updatedAt: .updated_at
        }]' >"$tmp/$1.json"
}

# One item per watched repo whose default branch has failed checks.
checks() {
  local repo=$1 page=1 runs="$tmp/runs-${1//\//-}"
  : >"$runs"
  # 100 runs a page: a failure on a later page must not be missed.
  while :; do
    get "$api/repos/$repo/commits/HEAD/check-runs?per_page=100&page=$page" >"$runs.page" || return 1
    jq --compact-output '.check_runs[]' "$runs.page" >>"$runs" || return 1
    if [ "$(jq '.check_runs | length' "$runs.page")" -lt 100 ]; then break; fi
    page=$((page + 1))
    if [ "$page" -gt 10 ]; then return 1; fi
  done
  jq --slurp --arg repo "$repo" '
    [.[] | select(.conclusion == "failure" or .conclusion == "timed_out")] as $failed
    | if ($failed | length) == 0 then [] else [{
        id: "checks:\($repo)",
        title: "\($repo): \($failed | length) failing on the default branch",
        url: "https://github.com/\($repo)/actions",
        detail: ($failed | map(.name) | unique | join(", ")),
        source: "CI",
        severity: "critical",
        updatedAt: ($failed | map(.completed_at) | max)
      }] end' "$runs" >"$tmp/checks-${repo//\//-}.json"
}

# Any failed request keeps the previous feed: a partial one would hide items.
if search failing warning "Checks failing" "author:$GITHUB_USER+status:failure" &&
  search changes warning "Changes requested" "author:$GITHUB_USER+review:changes_requested" &&
  search approved info "Approved" "author:$GITHUB_USER+review:approved+draft:false" &&
  search requested info "Review requested" "review-requested:$GITHUB_USER+draft:false"; then
  read -ra repos <<<"$WATCH_REPOS"
  for repo in "${repos[@]}"; do
    checks "$repo" || {
      echo "check-runs request for $repo failed; keeping the previous feed" >&2
      exit 0
    }
  done
else
  echo "a search request failed (rate limit or network); keeping the previous feed" >&2
  exit 0
fi

# Most severe first, then newest: Foyer shows only the first 50 items.
jq --slurp '{
  updatedAt: (now | todate),
  items: ((add // [])
    | sort_by(.updatedAt) | reverse
    | sort_by({critical: 0, warning: 1}[.severity] // 2))
}' "$tmp"/*.json >"$tmp/feed"
chmod 0644 "$tmp/feed"
# Rename within the feed directory: readers never see a half-written file.
cp "$tmp/feed" "$FEED_DIR/.attention.json.new"
mv "$FEED_DIR/.attention.json.new" "$FEED_DIR/attention.json"
echo "wrote $(jq '.items | length' "$FEED_DIR/attention.json") items"
