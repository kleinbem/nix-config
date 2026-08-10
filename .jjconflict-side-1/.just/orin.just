# Orin Nano Operations
#
# Recipes here run in two contexts:
#   - On the Orin itself (when SSH'd in): `stats`, `logs-vision`, `logs-ai`, `ai-chat`.
#   - From the dev workstation via SSH:   `ping`, `tegrastats`, `logs`, `shell`.
#
# Orin is a pure headless edge device — no desktop specialisation. If you need
# a remote GUI on the rare occasion, `waypipe` a Wayland app from your dev box.
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

# ─── Remote recipes (run from the dev workstation via SSH) ────────

[group("Orin")]
ping:
    @ping -c 3 orin-nano.local

[group("Orin")]
tegrastats:
    @ssh root@orin-nano.local "tegrastats --interval 1000 | head -n 5"

[group("Orin")]
logs service="ollama":
    @ssh root@orin-nano.local "journalctl -u {{service}} -n 50 --no-pager"

[group("Orin")]
shell:
    @ssh root@orin-nano.local

# Forward a Wayland app from the Orin to your local display via SSH.
# The app must be installed on the Orin (most aren't — install per-host as needed).
# Example: `just orin::gui gnome-disk-utility`
[group("Orin")]
gui app:
    @waypipe ssh root@orin-nano.local "{{app}}"
