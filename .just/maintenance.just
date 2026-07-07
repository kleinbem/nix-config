import 'common.just'

set working-directory := ".."

# --- nix-config maintenance ---
# Workspace-level concerns (treefmt, cross-repo audits, GC, knowledge mgmt, …)
# stay in the meta-workspace `.just/maintenance.just`.

[group("Linter")]
check:
    @echo "✅ Verifying NixOS configuration..."
    @{{LOCK_CMD}} {{TIMER}} nix eval .#nixosConfigurations.nixos-nvme.config.system.build.toplevel {{OVERRIDES}} --impure

[group("Linter")]
check-hosts *args="--impure":
    @echo "🏗️  Verifying all Host Configurations (Evaluation & Build)..."
    @{{LOCK_CMD}} {{TIMER}} nix flake check . {{OVERRIDES}} {{args}}


[group("Updates")]
sync-agent:
    @echo "🤖 Syncing system context for Antigravity..."
    @./scripts/sync-agent-context.sh
    @timeout 30 jj diff --quiet docs/SYSTEM_REFERENCE.md docs/OPTIONS.md docs/IMPORTS.md 2>/dev/null; rc=$?; \
    if [ "$rc" -eq 124 ]; then \
        echo "  ⏱️  jj diff timed out after 30s — skipping doc-change check (apply not blocked)."; \
        echo "     (jj likely deadlocked on the working-copy lock; re-run sync-agent later.)"; \
    elif [ "$rc" -ne 0 ]; then \
        echo "  📝 Reference docs updated — already in jj working copy (@)."; \
        echo "     Commit when convenient: jj describe -m 'docs: auto-update AI reference docs'"; \
    fi

# Print downstream consumers of changed files. Use `--git` to scan modified files,
# or pass one or more paths. Catches the common AI mistake of editing a module
# without realizing other hosts consume it.
[group("Linter")]
impact *args="--git":
    @python3 ./scripts/impact.py {{args}}

# Check Switchboard-pattern conventions (no `options.*` in hosts/users; warn on
# unfamiliar namespaces in modules). Pass `--strict` to fail on warnings.
[group("Linter")]
lint-conventions *args="":
    @python3 ./scripts/lint-conventions.py {{args}}

# Run the pytest suite for `_nix_options.py` parser primitives.
# Catches regressions in OPTIONS.md / IMPORTS.md / impact.py before they ship.
[group("Linter")]
test-python *args="":
    @nix shell nixpkgs#python3Packages.pytest --command pytest ./scripts/tests/ {{args}}

# Lint Python scripts with ruff. Replaces flake8/pyflakes/pylint/isort in one
# fast tool. Use `--fix` to auto-fix safe issues. Use `lint-python --select X`
# to focus on specific rule codes. See https://docs.astral.sh/ruff/rules/
[group("Linter")]
lint-python *args="":
    @nix shell nixpkgs#ruff --command ruff check ./scripts/ {{args}}

# Format Python scripts with ruff format (black-compatible).
# Also runs as part of `just maintenance::fmt` via treefmt integration.
[group("Formatting")]
fmt-python *args="":
    @nix shell nixpkgs#ruff --command ruff format ./scripts/ {{args}}

[group("Cleanup")]
clean-launchers *args:
    @echo "🚀 Cleaning broken launchers..."
    @bash ./scripts/clean-launchers.sh {{args}}
