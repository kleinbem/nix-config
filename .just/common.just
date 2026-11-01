# --- Shared variables ---
# OVERRIDES point nix-config's sibling inputs at their local checkouts.

# nix-config directory (parent of this .just/ dir), or <repo>.ws/<name>/ in a
# jj workspace.
ROOT := parent_directory(justfile())

# Workspace root holding the sibling repos: ROOT's parent, or one level higher
# when ROOT is a jj workspace (its parent dir ends in `.ws`).
META := if trim_end_match(file_name(parent_directory(ROOT)), ".ws") == file_name(parent_directory(ROOT)) {
    absolute_path(ROOT / "..")
} else {
    absolute_path(ROOT / "../..")
}

# Sibling nix-* checkouts used as input overrides. Excluded: nix-toolbox and
# *.ws dirs (not inputs, so nix warns), and nix-secrets* leftovers (a dot in the
# name is parsed as an input attribute path and the eval errors out).
SIBLING_REPOS := shell("find '" + META + "' -mindepth 1 -maxdepth 1 -name 'nix-*' -type d -not -name 'nix-config' -not -name 'nix-secrets*' -not -name 'nix-toolbox' -not -name '*.ws' -printf '%f\n' 2>/dev/null | xargs echo -n")

# `--override-input nix-X git+file:///abs/meta/nix-X` for every sibling,
# plus kleinbem-secrets explicitly since its directory name doesn't match
# the "nix-*" glob SIBLING_REPOS uses.
OVERRIDES := shell("echo '" + SIBLING_REPOS + "' | sed -E 's|([^ ]+)|--override-input \\1 git+file://" + META + "/\\1|g'") + " --override-input kleinbem-secrets git+file://" + META + "/kleinbem-secrets"

KEEP      := "3"
TIMER     := "time "
LOCK_FILE := "/tmp/nix-config-just.lock"
LOCK_CMD := "bash -c 'if ! flock -n 9; then echo \"❌ ERROR: Workspace locked by another process at " + LOCK_FILE + ". Run \\`just maintenance::who\\` to check.\"; exit 1; fi; \"$@\"' 9>>" + LOCK_FILE + " -- "
