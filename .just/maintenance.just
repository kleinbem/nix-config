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

[private]
_apply switch_target auth="":
    #!/usr/bin/env bash
    set -e
    if [ "{{auth}}" = "sudo" ] || [ "{{auth}}" = "preauth" ] || [ "{{auth}}" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    fi
    # Meta-workspace concerns: invoke from the parent justfile.
    just -f ../justfile git::stage-all
    just -f ../justfile maintenance::update-local
    just maintenance::check
    just nixos::{{switch_target}} "{{auth}}"
    just maintenance::sync-agent

[group("Workflow")]
apply auth="":
    @just maintenance::_apply "switch" "{{auth}}"

[group("Workflow")]
apply-fast auth="" *args="":
    #!/usr/bin/env bash
    set -e
    if [ "{{auth}}" = "sudo" ] || [ "{{auth}}" = "preauth" ] || [ "{{auth}}" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    fi
    just -f ../justfile git::stage-all
    just -f ../justfile maintenance::update-local
    just nixos::switch "{{auth}}" "" {{args}}
    just maintenance::sync-agent

[group("Workflow")]
apply-boot auth="":
    @just maintenance::_apply "switch-boot" "{{auth}}"

[group("Updates")]
sync-agent:
    @echo "🤖 Syncing system context for Antigravity..."
    @./scripts/sync-agent-context.sh
    @if ! git diff --quiet docs/SYSTEM_REFERENCE.md docs/OPTIONS.md docs/IMPORTS.md 2>/dev/null; then \
        git add docs/SYSTEM_REFERENCE.md docs/OPTIONS.md docs/IMPORTS.md; \
        echo "  📝 Reference docs updated and staged — not committed (avoids FIDO PIN in nested subprocess)."; \
        echo "     Commit when convenient: git commit -m \"docs: auto-update AI reference docs\""; \
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
