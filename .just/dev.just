import 'common.just'

set working-directory := ".."

# --- Local Development Workflows ---

# Probe cache coverage; exit 0 = cached, 1 = would build locally, 2 = probe failed.
# Assembly-only drvs (activation, units, sops manifests, preferLocalBuild) count
# as covered: CI's placeholder secrets mean they never match its cache.
[group("Development")]
attic-coverage host="$(hostname)":
    #!/usr/bin/env bash
    set -uo pipefail
    echo "🔍 Probing cache coverage for {{host}} closure..."
    rc=0
    output=$({{LOCK_CMD}} nix build --no-link --dry-run .#nixosConfigurations.{{host}}.config.system.build.toplevel {{OVERRIDES}} --impure 2>&1) || rc=$?
    if [ "$rc" -ne 0 ]; then
        # An evaluation error leaves no "will be built" list either; don't report it as covered.
        echo "❌ Coverage probe failed (exit $rc) — the closure doesn't evaluate or build-plan:"
        echo "$output" | grep -iE 'error' | head -5
        exit 2
    fi
    mapfile -t built < <(echo "$output" | sed -n '/will be built:/,/will be fetched\|^$/p' | grep -oE '/nix/store/[^ ]+\.drv')
    if [ "${#built[@]}" -eq 0 ]; then
        echo "✓ Closure fully covered by Attic + cache.nixos.org — apply will only download."
        exit 0
    fi
    prefer_local=$(nix derivation show "${built[@]}" 2>/dev/null \
        | jq -r '(.derivations // .) | to_entries[] | select(.value.env.preferLocalBuild == "1" or .value.structuredAttrs.preferLocalBuild == true) | .key | sub(".*/"; "")')
    assembly='^(nixos-system-.*|activate|dry-activate|etc|system-units|user-units|unit-.*|manifest(-for-users)?\.json|boot\.json|append-initrd-secrets)$'
    heavy=()
    small=0
    for drv in "${built[@]}"; do
        base=${drv##*/}
        name=${base:33}
        name=${name%.drv}
        if [[ "$name" =~ $assembly ]] || grep -qxF "$base" <<<"$prefer_local"; then
            small=$((small + 1))
        else
            heavy+=("$drv")
        fi
    done
    if [ "${#heavy[@]}" -eq 0 ]; then
        echo "✓ Covered except $small small system-assembly steps (build locally in seconds)."
        exit 0
    fi
    echo "⚠️  ${#heavy[@]} derivations would build locally (not in any cache), plus $small small system-assembly steps:"
    printf '  %s\n' "${heavy[@]}" | head -25
    echo ""
    echo "   Tip: commit + push so CI builds them → pulls into Attic → just jj::pull-all && just dev::apply {{host}}"
    exit 1

[group("Development")]
apply *args="":
    #!/usr/bin/env bash
    set -euo pipefail
    set -- {{args}}

    TARGET_HOST="$(hostname)"
    MODE="switch"
    FAST=0
    DEBUG=0
    AUTH=""
    ROLLBACK=0
    ALLOW_LOCAL=0

    show_help() {
        cat <<'HELP'
    Usage: just dev::apply [HOST] [FLAGS]

    Align sub-flakes with origin/main, evaluate the host
    closure, surface any paths not yet in Attic, and switch the system.
    If HOST is provided, applies to that remote device using nixos-rebuild.

    Mode flags (mutually exclusive):
      (default)         Build the current config, activate it immediately, AND set as boot default.
      --boot            Build and set as boot default ONLY (activates on next reboot).
      --rollback        Roll back to the previous system generation.

    Modifiers (composable with each other and with mode flags):
      --fast            Skip the eval check + attic-coverage probe.
                        Use when you trust the current state and want speed.
      --debug           Verbose nh output + --show-trace on the build.
      --auth sudo       Cache the sudo timestamp up front; avoids mid-run prompt.
      --allow-local-build
                        Don't ask when paths would build locally (CI not green yet).

      -h, --help        Print this help and exit.

    Examples:
      just dev::apply
      just dev::apply core-pi
      just dev::apply core-pi --fast
      just dev::apply --boot --fast
      just dev::apply --debug --auth sudo
      just dev::apply --rollback
    HELP
    }

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) show_help; exit 0 ;;
            --fast) FAST=1; shift ;;
            --debug) DEBUG=1; shift ;;
            --boot) MODE="boot"; shift ;;
            --rollback) ROLLBACK=1; shift ;;
            --allow-local-build) ALLOW_LOCAL=1; shift ;;
            --auth) AUTH="$2"; shift 2 ;;
            --auth=*) AUTH="${1#--auth=}"; shift ;;
            -*) echo "❌ Unknown flag: $1" >&2; echo "Try: just dev::apply --help" >&2; exit 2 ;;
            *)
                # If we haven't seen a flag, it's the target host.
                # If it's `sudo`, it might be an auth argument passed strangely, but we support --auth=sudo.
                if [ "$1" = "sudo" ]; then AUTH="sudo"; else TARGET_HOST="$1"; fi
                shift
                ;;
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
        echo "↩️  Rolling back system to previous generation on $TARGET_HOST..."
        if [ "$TARGET_HOST" = "$(hostname)" ]; then
            {{LOCK_CMD}} nh os switch --rollback . -- {{OVERRIDES}}
        else
            echo "Remote rollback via nixos-rebuild not yet implemented."
            exit 1
        fi
        exit 0
    fi

    # 1. Align with CI's last green build (fetch + rebase every sub-repo)
    if [ -f ../nix/justfile ]; then just -f ../nix/justfile jj::pull-all; elif [ -f ../justfile ]; then just -f ../justfile jj::pull-all; fi

    # No lockfile re-pin: builds pass OVERRIDES and CI bumps the sibling pins on
    # main; uncommitted re-pins conflict on the next pull. By hand if needed:
    # `just maintenance::update-local` in nix/.

    # 2. Eval check + cache coverage (skipped with --fast)
    if [ "$FAST" -eq 0 ]; then
        if [ "$TARGET_HOST" = "$(hostname)" ]; then
            just dev::check
        else
            echo "✅ Verifying NixOS configuration for $TARGET_HOST..."
            {{LOCK_CMD}} {{TIMER}} nix eval .#nixosConfigurations."$TARGET_HOST".config.system.build.toplevel.drvPath {{OVERRIDES}} --impure
        fi
        cov=0
        just dev::attic-coverage "$TARGET_HOST" || cov=$?
        if [ "$cov" -eq 2 ]; then
            echo "❌ Not applying: the coverage probe failed." >&2
            exit 1
        fi
        if [ "$cov" -eq 1 ] && [ "$ALLOW_LOCAL" -eq 0 ]; then
            # Usually CI for this commit isn't green or hasn't pushed to Attic yet;
            # building locally can take hours.
            if [ -t 0 ]; then
                read -r -p "Build these locally anyway? [y/N] " answer
                # Strip stray whitespace/CR (some terminal modes send \r with Enter).
                answer=$(printf '%s' "$answer" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
                case "$answer" in y|yes) ;; *) echo "Not applying. Wait for CI, or rerun with --allow-local-build."; exit 1 ;; esac
            else
                echo "❌ Not applying: paths would build locally. Wait for CI, or rerun with --allow-local-build." >&2
                exit 1
            fi
        fi
    fi

    # 3. Deploy!
    if [ "$TARGET_HOST" = "$(hostname)" ]; then
        nh_mode="$MODE"
        [ "$MODE" = "boot" ] && nh_mode="switch-boot" # just nixos:: uses switch-boot mapping
        [ "$DEBUG" -eq 1 ] && nh_mode="$nh_mode-debug"
        just nixos::"$nh_mode" "$AUTH"
    else
        echo "🚀 Deploying $TARGET_HOST remotely using nixos-rebuild..."
        debug_flag=""
        [ "$DEBUG" -eq 1 ] && debug_flag="--show-trace"

        # nixos-rebuild's ssh subprocesses don't go through the ssh alias from
        # hosts/nixos-nvme/ssh-fido-recovery.nix, so mirror its fixes: terminal
        # PIN entry (SSH_ASKPASS_REQUIRE=never), then usbreset/agent restart.
        export SSH_ASKPASS_REQUIRE=never
        yubikey_id="1050:0406"
        errfile="$(mktemp)"
        trap 'rm -f "$errfile"' EXIT

        is_fido_glitch() {
            grep -qE 'sign_and_send_pubkey.*(invalid format|agent refused operation)|Connection closed by.*port 22|failed to start SSH connection' "$errfile"
        }

        export NIX_SSHOPTS="${NIX_SSHOPTS:-} -A"
        try_deploy() {
            : >"$errfile"
            # --no-reexec: prevents cross-architecture deployments (e.g. x86_64 -> aarch64)
            # from re-executing into the target architecture's nixos-rebuild under QEMU user emulation.
            nixos-rebuild "$MODE" --no-reexec --target-host "$TARGET_HOST" --build-host "$TARGET_HOST" --elevate=sudo --ask-elevate-password --flake .#"$TARGET_HOST" {{OVERRIDES}} $debug_flag 2> >(tee "$errfile" >&2)
        }

        if try_deploy; then
            :
        else
            status=$?
            if is_fido_glitch; then
                echo "⚠️  Detected FIDO2/SSH signing glitch — resetting YubiKey ($yubikey_id) and retrying..." >&2
                usbreset "$yubikey_id" >/dev/null 2>&1 || true
                sleep 1
                if try_deploy; then
                    :
                else
                    status=$?
                    if is_fido_glitch; then
                        echo "⚠️  Still glitching after USB reset — restarting ssh-agent and retrying once more..." >&2
                        systemctl --user restart ssh-agent.service 2>/dev/null || true
                        sleep 1
                        try_deploy
                    else
                        exit "$status"
                    fi
                fi
            else
                exit "$status"
            fi
        fi

        just deployment::push-cache --remote "$TARGET_HOST"
    fi

    # Reference docs are regenerated by CI (sync-docs.yaml) on every PR;
    # writing them here would leave the checkout dirty.

# Before pushing to main: formatting, CI's pre-commit-check and the host evaluation.
[group("Development")]
preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🧹 Formatting (treefmt, whole tree)..."
    nix fmt -- --fail-on-change
    echo "🔎 pre-commit-check (as CI)..."
    {{LOCK_CMD}} nix build --no-link ".#checks.$(nix eval --raw --impure --expr builtins.currentSystem).pre-commit-check" {{OVERRIDES}} --impure
    just dev::check
    echo "✅ Preflight passed."

# (`nix eval` of the toplevel itself prints evaluation errors inline and exits 0.)
# Evaluate the host's derivation path, so evaluation errors fail.
[group("Development")]
check:
    @echo "✅ Verifying NixOS configuration..."
    @{{LOCK_CMD}} {{TIMER}} nix eval .#nixosConfigurations.nixos-nvme.config.system.build.toplevel.drvPath {{OVERRIDES}} --impure

[group("Development")]
check-hosts *args="--impure":
    @echo "🏗️  Verifying all Host Configurations (Evaluation & Build)..."
    @{{LOCK_CMD}} {{TIMER}} nix flake check . {{OVERRIDES}} {{args}}

[group("Development")]
sync-agent:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "🤖 Syncing system context for Antigravity..."
    ./scripts/sync-agent-context.sh
    # jj diff briefly contends for the working-copy lock with other jj
    # activity (e.g. a jj-aware shell prompt polling status) — retry once
    # after a short wait before giving up, rather than treating one 30s
    # stall as a deadlock.
    timeout 15 jj diff --quiet docs/SYSTEM_REFERENCE.md docs/OPTIONS.md docs/IMPORTS.md 2>/dev/null
    rc=$?
    if [ "$rc" -eq 124 ]; then
        sleep 2
        timeout 15 jj diff --quiet docs/SYSTEM_REFERENCE.md docs/OPTIONS.md docs/IMPORTS.md 2>/dev/null
        rc=$?
    fi
    if [ "$rc" -eq 124 ]; then
        echo "  ⏱️  jj diff timed out after retrying — skipping doc-change check (apply not blocked)."
        echo "     (jj working-copy lock stayed held; re-run sync-agent later.)"
    elif [ "$rc" -ne 0 ]; then
        echo "  📝 Reference docs updated — already in jj working copy (@)."
        echo "     Commit when convenient: jj describe -m 'docs: auto-update AI reference docs'"
    fi

[group("Development")]
impact *args="--git":
    @python3 ./scripts/impact.py {{args}}

[group("Development")]
lint-conventions *args="":
    @python3 ./scripts/lint-conventions.py {{args}}

[group("Development")]
test-python *args="":
    @nix shell nixpkgs#python3Packages.pytest --command pytest ./scripts/tests/ {{args}}

[group("Development")]
lint-python *args="":
    @nix shell nixpkgs#ruff --command ruff check ./scripts/ {{args}}

[group("Development")]
fmt-python *args="":
    @nix shell nixpkgs#ruff --command ruff format ./scripts/ {{args}}
