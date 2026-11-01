# Orin Nano operations. `stats`, `logs-vision`, `logs-ai`, `ai-chat` run on the
# Orin itself; `ping`, `tegrastats`, `logs`, `shell`, `gui` run from the workstation.
import 'common.just'

set working-directory := ".."

# ─── On-device recipes (run when SSH'd into the Orin) ─────────────

[group("Orin")]
stats:
    @echo "📊 Opening Jetson Hardware Monitor..."
    jtop

[group("Orin")]
logs-vision:
    @echo "📹 Streaming Frigate logs..."
    journalctl -u container@frigate -f

[group("Orin")]
logs-ai:
    @echo "🤖 Streaming llama-cpp logs..."
    journalctl -u container@llama-cpp -f

[group("Orin")]
ai-chat:
    @echo "💬 Opening local chat interface..."
    # Connects to the local llama-cpp endpoint
    curl -s http://localhost:8080/v1/models | jq

# Run a manual test build of mesh-llm on-device with memory-safe concurrency (2 cores),
# temporarily suspending background mesh-llm to free unified VRAM if running.
[group("Orin")]
test-mesh path=".":
    @echo "🔨 Testing mesh-llm on-device (cores=2)..."
    @bash -c ' \
      stopped=0; \
      if systemctl is-active --quiet mesh-llm; then \
        echo "⏸️  Temporarily suspending background mesh-llm to free unified RAM..."; \
        sudo systemctl stop mesh-llm && stopped=1; \
      fi; \
      trap "[ \$$stopped -eq 1 ] && sudo systemctl start mesh-llm" EXIT; \
      cargo test --manifest-path {{path}}/Cargo.toml -j 2 \
    '

# Run a manual Nix package build on-device with memory-safe concurrency (2 cores),
# temporarily freeing unified RAM.
[group("Orin")]
build-mesh flake="github:kleinbem/nixpkgs#mesh-llm":
    @echo "🏗️ Building {{flake}} on-device (cores=2)..."
    @bash -c ' \
      stopped=0; \
      if systemctl is-active --quiet mesh-llm; then \
        echo "⏸️  Temporarily suspending background mesh-llm to free unified RAM..."; \
        sudo systemctl stop mesh-llm && stopped=1; \
      fi; \
      trap "[ \$$stopped -eq 1 ] && sudo systemctl start mesh-llm" EXIT; \
      nix build -L --keep-going --max-jobs 1 --cores 2 --no-link {{flake}} \
    '

# ─── Remote recipes (run from the dev workstation via SSH) ────────

[group("Orin")]
build-remote drv:
    @echo "🏗️ Triggering build on orin-nano (cores=2)..."
    @ssh -t martin@orin-nano.local "nix build -L --max-jobs 1 --cores 2 --no-link '{{drv}}'"

[group("Orin")]
ping:
    @ping -c 3 orin-nano.local

[group("Orin")]
tegrastats:
    @ssh -t martin@orin-nano.local "sudo tegrastats --interval 1000 | head -n 5"

[group("Orin")]
logs service="ollama":
    @ssh martin@orin-nano.local "journalctl -u {{service}} -n 50 --no-pager"

[group("Orin")]
shell:
    @ssh martin@orin-nano.local

# Forward a Wayland app from the Orin to your local display via SSH.
# The app must be installed on the Orin (most aren't — install per-host as needed).
# Example: `just orin::gui gnome-disk-utility`
[group("Orin")]
gui app:
    @waypipe ssh martin@orin-nano.local "{{app}}"
