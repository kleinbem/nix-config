# Justfile

# Default: Show available commands

default:
    @just --list

# --- Build & Deployment ---

# Build the system (No Switch)

build:
    nh os build .

# System Test (Build & Activate, No Bootloader)

test:
    nh os test .

# System Switch (Build & Activate & Bootloader)

switch:
    nh os switch .

# System Boot (Build & Bootloader only, No Switch)

boot:
    nh os boot .

# Switch with local overrides (Useful for secrets testing)

switch-local:
    nh os switch . -- \
      --override-input nix-secrets "path:${HOME}/Develop/github.com/kleinbem/nix/nix-secrets" \
      --override-input nix-hardware "path:${HOME}/Develop/github.com/kleinbem/nix/nix-hardware" \
      --override-input nix-devshells "path:${HOME}/Develop/github.com/kleinbem/nix/nix-devshells" \
      --override-input nix-presets "path:${HOME}/Develop/github.com/kleinbem/nix/nix-presets" \
      --override-input nix-packages "path:${HOME}/Develop/github.com/kleinbem/nix/nix-packages" \
      --override-input nix-templates "path:${HOME}/Develop/github.com/kleinbem/nix/nix-templates"

# Boot with local overrides

boot-local:
    nh os boot . -- \
      --override-input nix-secrets "path:${HOME}/Develop/github.com/kleinbem/nix/nix-secrets" \
      --override-input nix-hardware "path:${HOME}/Develop/github.com/kleinbem/nix/nix-hardware" \
      --override-input nix-devshells "path:${HOME}/Develop/github.com/kleinbem/nix/nix-devshells" \
      --override-input nix-presets "path:${HOME}/Develop/github.com/kleinbem/nix/nix-presets" \
      --override-input nix-packages "path:${HOME}/Develop/github.com/kleinbem/nix/nix-packages" \
      --override-input nix-templates "path:${HOME}/Develop/github.com/kleinbem/nix/nix-templates"

# Switch with Debug Output

switch-debug:
    nh os switch . -- --show-trace --verbose || (echo "❌ Activation failed! Tailing logs..." && journalctl -n 20 --no-pager -u ollama.service -u open-webui.service && exit 1)

# Update Flake Lockfile

update:
    nix flake update

# Verify Deployment (Post-Switch Check)

verify:
    verify-system

# Run Flake Checks (CI Tests)

check:
    nix flake check

# Full Deployment Pipeline (Lint -> Check -> Test -> Switch -> Verify)

deploy: lint check test switch verify
    @echo "✅ System successfully deployed and verified!"

# --- Colmena (Multi-Host Deployment) ---

# Deploy to ALL managed hosts
deploy-all:
    colmena apply

# Deploy to a specific host by name
deploy-to host:
    colmena apply --on {{host}}

# Deploy to hosts matching a tag (e.g., "router", "raspberry-pi")
deploy-tag tag:
    colmena apply --on @{{tag}}

# Deploy locally only (same machine, like `switch`)
deploy-local:
    colmena apply-local --sudo

# Dry-run: show what would change without applying
deploy-dry:
    colmena apply --evaluator streaming --verbose --dry-activate

# Build all host configs without deploying
build-all:
    colmena build

# --- Code Platform ---

update-extensions:
    @nix-shell -p python311 python311Packages.toml python311Packages.requests --run "python3 scripts/update_extensions.py"

# --- AI Workflow ---

# Smart Rebuild (Checks build count first)

rebuild-smart:
    ./scripts/smart-switch.sh .

lint:
    nix develop --command statix check
    nix develop --command deadnix .

# Automatically fix linting errors

fix:
    nix develop --command statix fix
    nix develop --command deadnix -e .

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
    @OLLAMA_API_BASE=<http://127.0.0.1:11434> nix develop --command aider \
      --model ollama/qwen2.5-coder:7b \
      --editor-model ollama/qwen2.5-coder:7b

# Run Aider LOCALLY (Free, Private, Uses Ollama)

localDeep:
    # Ensure BOTH models are present
    @ollama pull deepseek-r1:8b
    @ollama pull qwen2.5-coder:7b
    # Run Aider with DeepSeek (Architect) and Qwen (Editor)
    @OLLAMA_API_BASE=<http://127.0.0.1:11434> nix develop --command aider \
      --model ollama/deepseek-r1:8b \
      --editor-model ollama/qwen2.5-coder:7b
