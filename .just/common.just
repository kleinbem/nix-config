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

# Sibling sub-flakes that nix-config depends on, discovered at parse time.
# kleinbem-secrets is excluded from this glob (it doesn't match "nix-*"
# anyway) and remapped explicitly below. Also excludes any leftover/archived
# "nix-secrets*" checkout by glob, not exact name, so a renamed/archived
# checkout (e.g. nix-secrets.deleted) can't leak back in as a bogus sibling —
# nix's flake CLI parses dots in --override-input names as nested attribute
# paths, so a stray "nix-secrets.deleted" directory here produces an
# "invalid flake input attribute path element" error instead of silently
# no-opping. nix-toolbox is also excluded: it matches "nix-*" but is a
# standalone dev-workflow toolset (nix-check-versions, nix-audit-deps, …),
# never a nix-config flake input — including it produced a real (if inert)
# "--override-input nix-toolbox ... does not match any input" warning on
# every eval.
SIBLING_REPOS := shell("find '" + META + "' -mindepth 1 -maxdepth 1 -name 'nix-*' -type d -not -name 'nix-config' -not -name 'nix-secrets*' -not -name 'nix-toolbox' -printf '%f\n' 2>/dev/null | xargs echo -n")

# `--override-input nix-X git+file:///abs/meta/nix-X` for every sibling,
# plus kleinbem-secrets explicitly since its directory name doesn't match
# the "nix-*" glob SIBLING_REPOS uses.
OVERRIDES := shell("echo '" + SIBLING_REPOS + "' | sed -E 's|([^ ]+)|--override-input \\1 git+file://" + META + "/\\1|g'") + " --override-input kleinbem-secrets git+file://" + META + "/kleinbem-secrets"

KEEP      := "3"
TIMER     := "time "
LOCK_FILE := "/tmp/nix-config-just.lock"
LOCK_CMD := "bash -c 'if ! flock -n 9; then echo \"❌ ERROR: Workspace locked by another process at " + LOCK_FILE + ". Run \\`just maintenance::who\\` to check.\"; exit 1; fi; \"$@\"' 9>>" + LOCK_FILE + " -- "
