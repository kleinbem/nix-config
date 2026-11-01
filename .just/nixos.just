import 'common.just'

set working-directory := ".."

# --- NixOS Operations ---

[group("System")]
switch auth="" mode="" *args="":
    #!/usr/bin/env bash
    set -euo pipefail
    ACTUAL_MODE="{{mode}}"
    if [ "{{auth}}" = "sudo" ] || [ "{{auth}}" = "preauth" ] || [ "{{auth}}" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    else
        if [ -n "{{auth}}" ]; then
            ACTUAL_MODE="{{auth}}"
        fi
    fi
    echo "🏗️ Switching System Configuration..."
    if [ -n "$ACTUAL_MODE" ]; then
        {{LOCK_CMD}} {{TIMER}} nh os switch . --specialisation "$ACTUAL_MODE" -- {{OVERRIDES}} {{args}}
    else
        {{LOCK_CMD}} {{TIMER}} nh os switch . -- {{OVERRIDES}} {{args}}
    fi
    just deployment::push-cache "$(hostname)"

[group("System")]
build *args="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔨 Building System Configuration..."
    {{LOCK_CMD}} {{TIMER}} nh os build . -- {{OVERRIDES}} {{args}}
    just deployment::push-cache "$(hostname)"

[group("Development")]
dry-run *args="":
    @echo "🧪 Dry Run: Testing configuration activation..."
    @{{LOCK_CMD}} {{TIMER}} nh os test . --dry -- {{OVERRIDES}} {{args}}

[group("Development")]
test *args="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🚦 Testing System Configuration (Activation Only)..."
    {{LOCK_CMD}} {{TIMER}} nh os test . -- {{OVERRIDES}} {{args}}
    just deployment::push-cache "$(hostname)"

[group("System")]
[confirm("👢 This will make the current configuration the DEFAULT at boot. Proceed?")]
switch-boot auth="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{auth}}" = "sudo" ] || [ "{{auth}}" = "preauth" ] || [ "{{auth}}" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    fi
    echo "👢 Building and setting as boot default..."
    {{LOCK_CMD}} nh os boot . -- {{OVERRIDES}}
    just deployment::push-cache "$(hostname)"

[group("Debugging")]
switch-debug auth="" mode="" *args="":
    #!/usr/bin/env bash
    set -euo pipefail
    ACTUAL_MODE="{{mode}}"
    if [ "{{auth}}" = "sudo" ] || [ "{{auth}}" = "preauth" ] || [ "{{auth}}" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    else
        if [ -n "{{auth}}" ]; then
            ACTUAL_MODE="{{auth}}"
        fi
    fi
    echo "🐛 Switching with trace output..."
    if [ -n "$ACTUAL_MODE" ]; then
        {{LOCK_CMD}} nh os switch . --specialisation "$ACTUAL_MODE" -- --show-trace --verbose {{OVERRIDES}} {{args}}
    else
        {{LOCK_CMD}} nh os switch . -- --show-trace --verbose {{OVERRIDES}} {{args}}
    fi
    just deployment::push-cache "$(hostname)"

[group("Debugging")]
switch-boot-debug auth="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{auth}}" = "sudo" ] || [ "{{auth}}" = "preauth" ] || [ "{{auth}}" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    fi
    echo "👢 Debugging bootloader generation..."
    {{LOCK_CMD}} nh os boot . -- --show-trace --verbose {{OVERRIDES}}
    just deployment::push-cache "$(hostname)"

[group("Development")]
sys-plan:
    @echo "📋 Reviewing system derivation changes..."
    @{{LOCK_CMD}} nix build .#nixosConfigurations.nixos-nvme.config.system.build.toplevel --no-link --print-out-paths {{OVERRIDES}} > /tmp/new-system
    @{{LOCK_CMD}} nvd diff /run/current-system $(cat /tmp/new-system)

[group("Development")]
build-pkg pkg_name:
    @echo "📦 Building package: {{pkg_name}}..."
    @{{LOCK_CMD}} {{TIMER}} nix build .#{{pkg_name}} {{OVERRIDES}}

[group("Development")]
test-integration *args="":
    @echo "🧪 Running ALL integration tests..."
    @{{LOCK_CMD}} {{TIMER}} nix flake check . --system x86_64-linux {{OVERRIDES}} {{args}}

[group("Development")]
test-caddy *args="":
    @echo "🧪 Running TARGETED Caddy integration test..."
    @{{LOCK_CMD}} nix build .#checks.x86_64-linux.caddy-test {{OVERRIDES}} {{args}}

[group("Development")]
test-recovery *args="":
    @echo "🧪 Running Recovery & Restore integration test..."
    @{{LOCK_CMD}} nix build .#checks.x86_64-linux.recovery-test {{OVERRIDES}} {{args}}

[group("Development")]
test-vm *args="":
    @echo "🖥️ Building and launching test VM..."
    @{{LOCK_CMD}} {{TIMER}} nix build .#nixosConfigurations.nixos-nvme.config.system.build.vm {{OVERRIDES}} {{args}}
    @mkdir -p /var/lib/qemu/images
    NIX_DISK_IMAGE=/var/lib/qemu/images/nixos-nvme.qcow2 ./result/bin/run-nixos-nvme-vm

# --- Workload Profile Management (Specialisations) ---

[group("Modes")]
modes:
    @echo "🎭 Available System Modes:"
    @nix eval .#nixosConfigurations.nixos-nvme.config.specialisation --keys

[group("Modes")]
mode name:
    @just nixos::switch {{name}}

[group("Modes")]
reset-mode *args="":
    @{{LOCK_CMD}} nh os switch . -- {{OVERRIDES}} {{args}}
    @just deployment::push-cache "$(hostname)"

[group("Debugging")]
verify-caddy:
    @echo "🔍 Verifying Caddy Gateway..."
    @for i in {1..5}; do curl -k -s https://10.85.46.107 > /dev/null && echo "✅ Caddy is responsive" && exit 0 || echo "⏳ Waiting for Caddy... ($i/5)" && sleep 2; done
    @echo "❌ Caddy is NOT responsive. Checking status..."
    @systemctl status container@caddy.service --no-pager || true
    @echo "📜 Recent Logs:"
    @journalctl -u container@caddy.service -n 20 --no-pager

[group("Development")]
topology:
    @echo "🗺️ Rendering Infrastructure Topology..."
    @nix build .#topology.x86_64-linux.config.build.svg --no-link --print-out-paths > /tmp/topo-path
    @echo "✅ Rendered to: $(cat /tmp/topo-path)/main.svg"
    @if [ -n "$DISPLAY" ]; then xdg-open "$(cat /tmp/topo-path)/main.svg"; else echo "🔗 File path: $(cat /tmp/topo-path)/main.svg"; fi

# Attic client with the admin token from sops, e.g.
#   just nixos::attic cache info system
#   just nixos::attic cache configure system --private
# The config (with the token) lives on tmpfs for this one command, so no
# token sits in ~/.config/attic any more.
[group("System")]
[doc("Run the attic client with the admin token from sops (tmpfs config, nothing left in ~/.config/attic). E.g. `cache info system`.")]
attic *args:
    #!/usr/bin/env bash
    set -euo pipefail
    cfg=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}")
    trap 'rm -rf "$cfg"' EXIT
    mkdir -p "$cfg/attic"
    {
        printf 'default-server = "kleinbem"\n[servers.kleinbem]\nendpoint = "https://cache.kleinbem.dev/"\ntoken = "'
        sops -d --extract '["attic_admin_token"]' ../kleinbem-secrets/nix/per-host/nixos-nvme.yaml
        printf '"\n'
    } >"$cfg/attic/config.toml"
    XDG_CONFIG_HOME="$cfg" nix run nixpkgs#attic-client -- {{args}}

# Rotate the Attic signing key and re-issue every token (scripts/attic-rotate.sh).
[group("System")]
attic-rotate:
    @bash scripts/attic-rotate.sh

# Mint one token with the current signing key into sops (scripts/attic-mint.sh),
# e.g. `just nixos::attic-mint infra/terraform.yaml attic_ci_pull_token --sub github-ci-pull --pull system`.
[group("System")]
attic-mint file key *args:
    @bash scripts/attic-mint.sh {{ file }} {{ key }} {{ args }}

[group("System")]
attic-token:
    @echo "🔑 Generating new Attic Admin Token (Valid for 1y)..."
    #!/usr/bin/env bash
    ssh core-pi "sudo nixos-container run attic -- sh -c ' \\
      set -a; \\
      . /etc/atticd-env; \\
      if [ -z \"\$ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64\" ]; then \\
        export ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=\"\$ATTIC_SERVER_TOKEN_RS256_SECRET\"; \\
      fi; \\
      ATTICADM=\$(ls -1 /nix/store/*-attic-*/bin/atticadm | head -n 1); \\
      CONFIG=\$(ls -1 /nix/store/*-checked-attic-server.toml | head -n 1); \\
      \$ATTICADM -f \$CONFIG make-token --sub \"admin\" --validity \"1y\" --pull \"*\" --push \"*\" --create-cache \"*\" --configure-cache \"*\" --configure-cache-retention \"*\" --destroy-cache \"*\" \\
    '"

# For CI's ATTIC_PUSH_TOKEN (not the admin token above), e.g.:
#   TOKEN=$(just nixos::attic-ci-token | grep '^eyJ')
#   sops --set "[\"attic_push_token\"] \"$TOKEN\"" ../kleinbem-secrets/nix/per-host/orin-nano.yaml

# Mint a push/pull-only Attic token for one cache (no create/configure/destroy).
[group("System")]
attic-ci-token sub="github-ci" cache="system" validity="1y":
    #!/usr/bin/env bash
    set -euo pipefail
    ssh core-pi "sudo nixos-container run attic -- sh -c '
      set -a; . /etc/atticd-env
      [ -z \"\${ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64:-}\" ] && \
        export ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=\"\$ATTIC_SERVER_TOKEN_RS256_SECRET\"
      ATTICADM=\$(ls -1 /nix/store/*-attic-*/bin/atticadm | head -n 1)
      CONFIG=\$(ls -1 /nix/store/*-checked-attic-server.toml | head -n 1)
      \"\$ATTICADM\" -f \"\$CONFIG\" make-token \
        --sub \"{{ sub }}\" --validity \"{{ validity }}\" --pull \"{{ cache }}\" --push \"{{ cache }}\"
    '"

# Forces what the container's 12h timer does anyway: drop orphaned chunks and
# entries past the retention window (server default 14 days, see
# nix-presets/containers/attic.nix). To reclaim harder, shorten it, sweep,
# then restore it:
#   just nixos::attic cache configure system --retention-period 7d
#   just nixos::attic-gc
#   just nixos::attic-reap   # GC only marks chunks; this unlinks them
# A second atticd runs against the live SQLite DB, so "database is locked"
# can happen: just re-run it (the sweep runs inside the container, so it
# needs the container up).

# Run a one-shot Attic garbage-collection sweep in the cache container.
[group("System")]
attic-gc:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🧹 Running one-shot Attic GC sweep in the cache container…"
    ssh core-pi "sudo nixos-container run attic -- sh -c '
      set -a; . /etc/atticd-env
      [ -z \"\${ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64:-}\" ] && \
        export ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=\"\$ATTIC_SERVER_TOKEN_RS256_SECRET\"
      ATTICD=\$(ls -1 /nix/store/*-attic-*/bin/atticd | head -n 1)
      CONFIG=\$(ls -1 /nix/store/*-checked-attic-server.toml | head -n 1)
      echo \"── storage BEFORE ──\"; du -sh /var/lib/atticd/storage 2>/dev/null || true
      echo \"▶ \$ATTICD --mode garbage-collector-once -f \$CONFIG\"
      \"\$ATTICD\" --mode garbage-collector-once -f \"\$CONFIG\"
      echo \"── storage AFTER ──\";  du -sh /var/lib/atticd/storage 2>/dev/null || true
    '"
    echo "✅ Attic GC sweep complete."

# On-demand run of the orphaned-chunk reaper (the same host service the weekly
# `autoReap` timer fires). atticd's retention GC marks superseded chunks deleted
# but never unlinks the files on core-pi; this reclaims them (+VACUUMs the DB).
# Safe: refuses if any deleted-marked chunk is still referenced, and defers if a
# push is writing chunks. `systemctl start` blocks until the oneshot finishes.
[group("System")]
attic-reap:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🧹 Running attic-reap on core-pi (reclaims orphaned chunks + VACUUM)…"
    ssh core-pi "sudo systemctl start attic-reap.service"
    ssh core-pi "sudo journalctl -u attic-reap.service -n 15 --no-pager --output cat"
    echo "✅ attic-reap complete."
