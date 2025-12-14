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

# --- AI Workflow ---

# Enter the AI Environment
dev:
    nix develop

# Run Aider (The Architect)
architect:
    nix develop --command aider

# Run Aider with a specific model (e.g. for coding)
code:
    nix develop --command aider --model deepseek/deepseek-chat

# Run Aider with Gemini (Reasoning)
plan:
    nix develop --command aider --model gemini/gemini-2.0-flash-thinking-exp
