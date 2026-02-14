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
      --override-input nix-secrets "path:/home/martin/Develop/github.com/kleinbem/nix/nix-secrets" \
      --override-input nix-hardware "path:/home/martin/Develop/github.com/kleinbem/nix/nix-hardware" \
      --override-input nix-devshells "path:/home/martin/Develop/github.com/kleinbem/nix/nix-devshells" \
      --override-input nix-presets "path:/home/martin/Develop/github.com/kleinbem/nix/nix-presets" \
      --override-input nix-packages "path:/home/martin/Develop/github.com/kleinbem/nix/nix-packages" \
      --override-input nix-templates "path:/home/martin/Develop/github.com/kleinbem/nix/nix-templates"

# Boot with local overrides

boot-local:
    nh os boot . -- \
      --override-input nix-secrets "path:/home/martin/Develop/github.com/kleinbem/nix/nix-secrets" \
      --override-input nix-hardware "path:/home/martin/Develop/github.com/kleinbem/nix/nix-hardware" \
      --override-input nix-devshells "path:/home/martin/Develop/github.com/kleinbem/nix/nix-devshells" \
      --override-input nix-presets "path:/home/martin/Develop/github.com/kleinbem/nix/nix-presets" \
      --override-input nix-packages "path:/home/martin/Develop/github.com/kleinbem/nix/nix-packages" \
      --override-input nix-templates "path:/home/martin/Develop/github.com/kleinbem/nix/nix-templates"

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

# --- Terranix Fleet Orchestration ---

# Build & Import n8n Image (Required before deploy)

import-n8n:
    @echo "📦 Building n8n image..."
    nix build .#n8n-image
    incus image delete n8n-image || true
    ./scripts/patch-incus-image.sh result/tarball/*.tar.xz "n8n-image" "NixOS n8n Container"

# Build & Import Open WebUI Image

import-open-webui:
    @echo "📦 Building Open WebUI image..."
    nix build .#open-webui-image
    incus image delete open-webui-image || true
    ./scripts/patch-incus-image.sh result/tarball/*.tar.xz "open-webui-image" "NixOS Open WebUI Container"

# Generate & Plan Infrastructure Changes

infra-plan:
    cd infra && nix run .
    cd infra && nix develop --command bash -c "tofu init && tofu plan"

# Generate & Apply Infrastructure Changes

infra-apply:
    cd infra && nix run .
    cd infra && nix develop --command bash -c "tofu init && tofu apply"

# Deploy Fleet (Non-Interactive)

infra-deploy:
    cd infra && nix run .
    cd infra && nix develop --command bash -c "tofu init && tofu apply -auto-approve"
