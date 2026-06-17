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

# Dry-run the system closure and surface anything not yet in Attic or cache.nixos.org.
# Informational only — does not block. A non-empty list means `apply` will build locally.
[group("Linter")]
attic-coverage:
    #!/usr/bin/env bash
    set -e
    echo "🔍 Probing cache coverage for nixos-nvme closure..."
    output=$({{LOCK_CMD}} nix build --no-link --dry-run .#nixosConfigurations.nixos-nvme.config.system.build.toplevel {{OVERRIDES}} --impure 2>&1) || true
    if echo "$output" | grep -qE "will be built"; then
        echo "⚠️  These derivations would build locally (not in any cache):"
        echo "$output" | sed -n '/will be built:/,/will be fetched\|^$/p' | grep -E '^\s+/nix/store' | head -25
        echo ""
        echo "   Tip: commit + push so CI builds them → pulls into Attic → just jj::pull-all && just apply"
    else
        echo "✓ Closure fully covered by Attic + cache.nixos.org — apply will only download."
    fi

# Unified apply: pull sub-flakes, sync locks, evaluate, surface cache misses, switch.
# All flags optional and composable (except --rollback and --help which short-circuit).
# Run `just apply --help` for the full menu.
[group("Workflow")]
apply *flags="":
    #!/usr/bin/env bash
    set -euo pipefail

    MODE="switch"
    FAST=0
    DEBUG=0
    AUTH=""
    ROLLBACK=0

    show_help() {
        cat <<'HELP'
    Usage: just apply [FLAGS]

    Align sub-flakes with origin/main, sync lockfiles, evaluate the host
    closure, surface any paths not yet in Attic, and switch the system.

    Mode flags (mutually exclusive):
      (default)         Build the current config and activate it.
      --boot            Activate AND set the new generation as boot default.
      --rollback        Roll back to the previous system generation.

    Modifiers (composable with each other and with mode flags):
      --fast            Skip the eval check + attic-coverage probe.
                        Use when you trust the current state and want speed.
      --debug           Verbose nh output + --show-trace on the build.
      --auth sudo       Cache the sudo timestamp up front; avoids mid-run prompt.

      -h, --help        Print this help and exit.

    Examples:
      just apply
      just apply --boot
      just apply --boot --fast
      just apply --debug --auth sudo
      just apply --rollback
    HELP
    }

    # Parse flags. {{flags}} is just's *flags variadic argument joined by spaces.
    set -- {{flags}}
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) show_help; exit 0 ;;
            --fast) FAST=1; shift ;;
            --debug) DEBUG=1; shift ;;
            --boot) MODE="switch-boot"; shift ;;
            --rollback) ROLLBACK=1; shift ;;
            --auth)
                if [ $# -ge 2 ]; then AUTH="$2"; shift 2;
                else echo "❌ --auth requires a value (e.g. --auth sudo)" >&2; exit 2; fi ;;
            --auth=*) AUTH="${1#--auth=}"; shift ;;
            "") shift ;;
            *) echo "❌ Unknown flag: $1" >&2; echo "Try: just apply --help" >&2; exit 2 ;;
        esac
    done

    # Cache sudo timestamp if requested
    if [ "$AUTH" = "sudo" ] || [ "$AUTH" = "preauth" ] || [ "$AUTH" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    fi

    # --rollback short-circuits everything else; no pull, no eval needed
    if [ "$ROLLBACK" -eq 1 ]; then
        echo "↩️  Rolling back system to previous generation..."
        {{LOCK_CMD}} nh os switch --rollback . -- {{OVERRIDES}}
        exit 0
    fi

    # 1. Align with CI's last green build (fetch + rebase every sub-repo)
    just -f ../justfile jj::pull-all

    # 2. Sync sub-flake lockfiles topologically
    just -f ../justfile maintenance::update-local

    # 3. Eval check + cache coverage (skipped with --fast)
    if [ "$FAST" -eq 0 ]; then
        just maintenance::check
        just maintenance::attic-coverage
    fi

    # 4. Switch (combine MODE × DEBUG into the right nixos:: target)
    target="$MODE"
    [ "$DEBUG" -eq 1 ] && target="$MODE-debug"
    just nixos::"$target" "$AUTH"

    # 5. Regenerate Antigravity reference docs
    just maintenance::sync-agent


[group("Updates")]
sync-agent:
    @echo "🤖 Syncing system context for Antigravity..."
    @./scripts/sync-agent-context.sh
    @if ! jj diff --quiet docs/SYSTEM_REFERENCE.md docs/OPTIONS.md docs/IMPORTS.md 2>/dev/null; then \
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
