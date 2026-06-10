import 'common.just'

set working-directory := ".."

# --- AI host operations (run against nix-config hosts) ---
# Meta-workspace AI tooling (Aider launchers, cross-repo knowledge sync)
# stays at the meta root in `.just/ai.just`.

[group("Status")]
ai-check:
    @echo "🩺 AI Stack Health Check"
    @curl -s http://localhost:11434/api/tags >/dev/null && echo "✅ Ollama: Online" || echo "❌ Ollama: Offline"
    @curl -s http://localhost:8000/health >/dev/null && echo "✅ vLLM: Online" || echo "❌ vLLM: Offline"

[group("Development")]
ai-shell:
    @echo "🐚 Entering AI DevShell..."
    @nix develop .#ai

[group("Debugging")]
ai-logs *args:
    @journalctl -p 3 -n 50 --no-pager {{args}} | nix run nixpkgs#llm -- "Explain these errors in simple terms and suggest fixes."

[group("Debugging")]
ai-team-logs:
    @echo "👥 Viewing Agent Team activity..."
    @tail -f /var/log/agent-team.log

[group("Workflow")]
ai-init-safe:
    @echo "🌡️ Starting AI stack in Safe Mode..."
    @systemctl start ollama.service
    @sleep 5
    @systemctl start vllm.service
    @echo "✅ AI Stack Ready."

[group("Development")]
ai-provision-models:
    @echo "📥 Pulling recommended local models..."
    @ollama pull nomic-embed-text
    @ollama pull llama3:8b

[group("Status")]
ai-health-fleet:
    @just ai::ai-check
    @echo "📡 Probing Orin Nano..."
    @just orin::ping && echo "✅ Orin: Reachable" || echo "❌ Orin: Unreachable"
