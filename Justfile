# Justfile

# Default: Show available commands
default:
    @just --list

# --- System Management ---

# Apply changes (Safe Mode)
test:
    sudo nixos-rebuild test --flake .#nixos-nvme

# Apply changes (Permanent)
switch:
    sudo nixos-rebuild switch --flake .#nixos-nvme

# Update dependencies (flake.lock)
update:
    nix flake update

# Run Lint -> Test -> Switch automatically
deploy: lint test switch
    @echo "✅ System successfully deployed and switched!"

# --- AI Workflow ---

# Check for linting errors (Statix)
lint:
    nix develop --command statix check
    nix develop --command deadnix .

# Enter the AI Environment
dev:
    nix develop

# Run Aider (The Architect) - Uses Gemini 2.0 Flash Thinking (Free API)
architect:
    nix develop --command aider

# Run Aider with DeepSeek API (Fast Coding)
code:
    nix develop --command aider --model deepseek/deepseek-chat

# Run Aider with Gemini Pro (Deep Reasoning)
plan:
    nix develop --command aider --model gemini/gemini-2.0-flash-thinking-exp

# Fast Local Mode (No Reasoning Wait)
local:
    @ollama pull qwen2.5-coder:7b
    @OLLAMA_API_BASE=http://127.0.0.1:11434 nix develop --command aider \
      --model ollama/qwen2.5-coder:7b \
      --editor-model ollama/qwen2.5-coder:7b

# Run Aider LOCALLY (Free, Private, Uses Ollama)
localDeep:
    # Ensure BOTH models are present
    @ollama pull deepseek-r1:8b 
    @ollama pull qwen2.5-coder:7b
    # Run Aider with DeepSeek (Architect) and Qwen (Editor)
    @OLLAMA_API_BASE=http://127.0.0.1:11434 nix develop --command aider \
      --model ollama/deepseek-r1:8b \
      --editor-model ollama/qwen2.5-coder:7b
