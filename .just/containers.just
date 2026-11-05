# Fleet container management (nspawn + nix-gantry)
import 'common.just'

set working-directory := ".."

# List containers and their active closure symlinks (local or remote)
[group("Containers")]
list host="":
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="{{ host }}"
    if [ -z "$TARGET" ] || [ "$TARGET" = "$(hostname)" ] || [ "$TARGET" = "localhost" ]; then
        echo "📦 Local Running Containers (machinectl):"
        sudo machinectl list --no-pager || true
        echo ""
        echo "🔗 Standalone Decoupled Container Closures (/var/lib/machines):"
        for d in /var/lib/machines/*; do
            if [ -L "$d/current" ]; then
                echo "  • $(basename "$d") -> $(readlink -f "$d/current")"
            fi
        done
    else
        echo "📦 [$TARGET] Running Containers (machinectl):"
        ssh -t "$TARGET" "sudo machinectl list --no-pager || true"
        echo ""
        echo "🔗 [$TARGET] Standalone Decoupled Container Closures (/var/lib/machines):"
        ssh -t "$TARGET" 'for d in /var/lib/machines/*; do if [ -L "$d/current" ]; then echo "  • $(basename "$d") -> $(readlink -f "$d/current")"; fi; done'
    fi

# Check systemd status of a container
[group("Containers")]
status name host="":
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="{{ host }}"
    if [ -z "$TARGET" ] || [ "$TARGET" = "$(hostname)" ] || [ "$TARGET" = "localhost" ]; then
        systemctl status "container@{{ name }}.service" --no-pager
    else
        ssh "$TARGET" "systemctl status 'container@{{ name }}.service' --no-pager"
    fi

# Tail logs for a container
[group("Containers")]
logs name host="" *args="":
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="{{ host }}"
    if [ -z "$TARGET" ] || [ "$TARGET" = "$(hostname)" ] || [ "$TARGET" = "localhost" ]; then
        journalctl -u "container@{{ name }}.service" -n 100 -f {{ args }}
    else
        ssh -t "$TARGET" "journalctl -u 'container@{{ name }}.service' -n 100 -f {{ args }}"
    fi

# Open an interactive shell inside a running container
[group("Containers")]
enter name host="":
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="{{ host }}"
    if [ -z "$TARGET" ] || [ "$TARGET" = "$(hostname)" ] || [ "$TARGET" = "localhost" ]; then
        sudo machinectl shell "{{ name }}" || sudo nixos-container root-login "{{ name }}"
    else
        ssh -t "$TARGET" "sudo machinectl shell '{{ name }}' || sudo nixos-container root-login '{{ name }}'"
    fi

# Restart a container
[group("Containers")]
restart name host="":
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="{{ host }}"
    if [ -z "$TARGET" ] || [ "$TARGET" = "$(hostname)" ] || [ "$TARGET" = "localhost" ]; then
        sudo systemctl restart "container@{{ name }}.service"
    else
        ssh -t "$TARGET" "sudo systemctl restart 'container@{{ name }}.service'"
    fi

# Trigger an immediate pull and activation from the container manifest (nix-gantry)
[group("Containers")]
update name host="":
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="{{ host }}"
    echo "🔄 Staging update for container '{{ name }}'..."
    if [ -z "$TARGET" ] || [ "$TARGET" = "$(hostname)" ] || [ "$TARGET" = "localhost" ]; then
        sudo systemctl start "update-container-stage@{{ name }}.service"
        echo "🚀 Activating updated container '{{ name }}'..."
        sudo systemctl start "update-container-activate@{{ name }}.service"
        echo "✅ Done. Active generation:"
        ls -l "/var/lib/machines/{{ name }}/current" || true
    else
        ssh -t "$TARGET" "sudo systemctl start 'update-container-stage@{{ name }}.service' && sudo systemctl start 'update-container-activate@{{ name }}.service'"
        echo "✅ Done on $TARGET. Active generation:"
        ssh "$TARGET" "ls -l '/var/lib/machines/{{ name }}/current' || true"
    fi

# Roll back a container to its previous generation
[group("Containers")]
rollback name host="":
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="{{ host }}"
    echo "⏪ Rolling back container '{{ name }}'..."
    if [ -z "$TARGET" ] || [ "$TARGET" = "$(hostname)" ] || [ "$TARGET" = "localhost" ]; then
        sudo systemctl start "update-container-rollback@{{ name }}.service"
        echo "✅ Done. Active generation:"
        ls -l "/var/lib/machines/{{ name }}/current" || true
    else
        ssh -t "$TARGET" "sudo systemctl start 'update-container-rollback@{{ name }}.service'"
        echo "✅ Done on $TARGET. Active generation:"
        ssh "$TARGET" "ls -l '/var/lib/machines/{{ name }}/current' || true"
    fi

# The tofu provider has no admin-token resource, so this recipe makes it.
# Scope is every read call garage-ui makes (GetKeyInfo to browse objects).
# Run on nixos-nvme, then commit kleinbem-secrets and `just dev::apply`.
#
# (Re)create garage-ui's read-only Garage admin token (nixos-nvme)
[group("Containers")]
garage-ui-token:
    #!/usr/bin/env bash
    set -euo pipefail
    SCOPE="GetClusterHealth,GetClusterStatus,GetClusterStatistics,GetNodeInfo,GetNodeStatistics,ListBuckets,GetBucketInfo,ListKeys,GetKeyInfo"
    NAME=garage-ui-readonly
    f=nix/per-container/garage-ui.yaml
    cd "{{ META }}/kleinbem-secrets"
    umask 077
    # Mint under a temporary name and swap only once sops has it, so a failed
    # run keeps the old token and leaves no plaintext behind.
    sudo garage admin-token delete --yes "$NAME-new" >/dev/null 2>&1 || true
    stored=0
    trap 'rm -f "$f.new"; [ "$stored" = 1 ] || sudo garage admin-token delete --yes "$NAME-new" >/dev/null 2>&1 || true' EXIT
    TOKEN=$(sudo garage admin-token create -q --scope "$SCOPE" "$NAME-new")
    [ -n "$TOKEN" ] || { echo "❌ garage returned an empty token; nothing written" >&2; exit 1; }
    if [ -f "$f" ]; then
        printf '%s' "$TOKEN" | jq -Rs . | sops set --value-stdin "$f" '["garage_ui_admin_token"]'
    else
        # The first secret creates the file, with the recipients from .sops.yaml.
        printf 'garage_ui_admin_token: %s\n' "$TOKEN" \
            | sops encrypt --input-type yaml --output-type yaml --filename-override "$f" /dev/stdin > "$f.new"
        mv "$f.new" "$f"
    fi
    stored=1
    unset TOKEN
    if sudo garage admin-token info "$NAME" >/dev/null 2>&1; then
        echo "♻️  Replacing the existing $NAME token..."
        sudo garage admin-token delete --yes "$NAME" >/dev/null
    fi
    sudo garage admin-token rename "$NAME-new" "$NAME" >/dev/null
    echo "✅ Read-only token stored in kleinbem-secrets/nix/per-container/garage-ui.yaml"
    echo "   Commit kleinbem-secrets, then: just dev::apply"
