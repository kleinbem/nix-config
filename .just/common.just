# --- Shared variables (nix-config standalone view) ---
#
# When this flake is consumed from the meta-workspace, the *meta* justfile's
# common.just generates OVERRIDES that point every sibling sub-flake (nix-presets,
# nix-hardware, …) at its local checkout. When `just` is run inside nix-config
# directly, we re-derive the same overrides for nix-config's own inputs — minus
# nix-config itself, since you can't override your own flake.

# nix-config directory (parent of this .just/ dir)
ROOT := parent_directory(justfile())

# Meta-workspace directory (parent of nix-config)
META := absolute_path(ROOT / "..")

# Sibling sub-flakes that nix-config depends on, discovered at parse time
SIBLING_REPOS := shell("find '" + META + "' -mindepth 1 -maxdepth 1 -name 'nix-*' -type d -not -name 'nix-config' -printf '%f\n' 2>/dev/null | xargs echo -n")

# `--override-input nix-X git+file:///abs/meta/nix-X` for every sibling
OVERRIDES := shell("echo '" + SIBLING_REPOS + "' | sed -E 's|([^ ]+)|--override-input \\1 git+file://" + META + "/\\1|g'")

KEEP      := "3"
TIMER     := "time "
LOCK_FILE := "/tmp/nix-config-just.lock"
LOCK_CMD := "bash -c 'if ! flock -n 9; then echo \"❌ ERROR: Workspace locked by another process at " + LOCK_FILE + ". Run \\`just maintenance::who\\` to check.\"; exit 1; fi; \"$@\"' 9>>" + LOCK_FILE + " -- "
