import 'common.just'

set working-directory := ".."

# --- Local Development Workflows ---

[group("Development")]
attic-coverage host="$(hostname)":
    #!/usr/bin/env bash
    set -e
    echo "🔍 Probing cache coverage for {{host}} closure..."
    output=$({{LOCK_CMD}} nix build --no-link --dry-run .#nixosConfigurations.{{host}}.config.system.build.toplevel {{OVERRIDES}} --impure 2>&1) || true
    if echo "$output" | grep -qE "will be built"; then
        echo "⚠️  These derivations would build locally (not in any cache):"
        echo "$output" | sed -n '/will be built:/,/will be fetched\|^$/p' | grep -E '^\s+/nix/store' | head -25
        echo ""
        echo "   Tip: commit + push so CI builds them → pulls into Attic → just jj::pull-all && just dev::apply {{host}}"
    else
        echo "✓ Closure fully covered by Attic + cache.nixos.org — apply will only download."
    fi

[group("Development")]
apply *args="":
    #!/usr/bin/env bash
    set -euo pipefail

    TARGET_HOST="$(hostname)"
    MODE="switch"
    FAST=0
    DEBUG=0
    AUTH=""
    ROLLBACK=0

    show_help() {
        cat <<'HELP'
    Usage: just dev::apply [HOST] [FLAGS]

    Align sub-flakes with origin/main, sync lockfiles, evaluate the host
    closure, surface any paths not yet in Attic, and switch the system.
    If HOST is provided, applies to that remote device using nixos-rebuild.

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
      just dev::apply
      just dev::apply core-pi
      just dev::apply core-pi --fast
      just dev::apply --boot --fast
      just dev::apply --debug --auth sudo
      just dev::apply --rollback
    HELP
    }

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            -h|--help) show_help; exit 0 ;;
            --fast) FAST=1 ;;
            --debug) DEBUG=1 ;;
            --boot) MODE="boot" ;;
            --rollback) ROLLBACK=1 ;;
            --auth=*) AUTH="${arg#--auth=}" ;;
            -*) echo "❌ Unknown flag: $arg" >&2; echo "Try: just dev::apply --help" >&2; exit 2 ;;
            *) 
                # If we haven't seen a flag, it's the target host. 
                # If it's `sudo`, it might be an auth argument passed strangely, but we support --auth=sudo.
                if [ "$arg" = "sudo" ]; then AUTH="sudo"; else TARGET_HOST="$arg"; fi
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
    just -f ../justfile jj::pull-all

    # 2. Sync sub-flake lockfiles topologically
    just -f ../justfile maintenance::update-local

    # 3. Eval check + cache coverage (skipped with --fast)
    if [ "$FAST" -eq 0 ]; then
        if [ "$TARGET_HOST" = "$(hostname)" ]; then
            just maintenance::check
        else
            echo "✅ Verifying NixOS configuration for $TARGET_HOST..."
            {{LOCK_CMD}} {{TIMER}} nix eval .#nixosConfigurations."$TARGET_HOST".config.system.build.toplevel {{OVERRIDES}} --impure
        fi
        just dev::attic-coverage "$TARGET_HOST"
    fi

    # 4. Deploy!
    if [ "$TARGET_HOST" = "$(hostname)" ]; then
        nh_mode="$MODE"
        [ "$MODE" = "boot" ] && nh_mode="switch-boot" # just nixos:: uses switch-boot mapping
        [ "$DEBUG" -eq 1 ] && nh_mode="$nh_mode-debug"
        just nixos::"$nh_mode" "$AUTH"
    else
        echo "🚀 Deploying $TARGET_HOST remotely using nixos-rebuild..."
        debug_flag=""
        [ "$DEBUG" -eq 1 ] && debug_flag="--show-trace"
        nixos-rebuild "$MODE" --target-host "$TARGET_HOST" --build-host "$TARGET_HOST" --use-remote-sudo --flake .#"$TARGET_HOST" {{OVERRIDES}} $debug_flag
    fi

    # 5. Regenerate Antigravity reference docs
    just maintenance::sync-agent
