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
