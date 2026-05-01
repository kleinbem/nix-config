#!/usr/bin/env bash

echo "🔍 Verifying System State..."

# 0. Check Code Quality (If in a flake repo)
if [ -n "${FLAKE:-}" ] && [ -d "$FLAKE" ]; then
  echo "Checking Code Quality..."
  cd "$FLAKE" || exit 1

  echo -n "  - Nix Formatting... "
  if nixfmt --check . &>/dev/null; then
    echo "✅ Passed"
  else
    echo "❌ FAILED (Run 'just lint' to fix)"
    # Optional: exit 1 to strict fail
  fi

  echo -n "  - Dead Code (deadnix)... "
  if deadnix --fail . &>/dev/null; then
    echo "✅ Passed"
  else
    echo "❌ FAILED (Run 'just lint' to fix)"
  fi

  echo -n "  - Anti-patterns (statix)... "
  if statix check . &>/dev/null; then
    echo "✅ Passed"
  else
    echo "❌ FAILED (Run 'just lint' to fix)"
  fi
else
  echo "ℹ️  Skipping Code Quality checks (FLAKE env var not set)"
fi

# 1. Check Core System
echo -n "Checking NixOS Version... "
if grep -q "NixOS" /etc/os-release; then
  echo "✅ $(uname -r)"
else
  echo "❌ NOT NixOS"
  exit 1
fi

echo -n "Checking Intel GPU Access... "
if [ -e /dev/dri/renderD128 ]; then
  echo "✅ Present (/dev/dri/renderD128)"
else
  echo "❌ MISSING GPU DEVICE"
  # Don't exit, might be headless?
fi

echo -n "Checking ZRAM Swap... "
if grep -q "/dev/zram" /proc/swaps; then
  echo "✅ Active"
else
  echo "❌ INACTIVE"
  exit 1
fi

# 2. Check Services
# We check valid services. If they are not running, systemctl returns non-zero.

echo -n "Checking vLLM Service... "
if systemctl is-active --quiet podman-vllm.service; then
  echo "✅ Active"
else
  echo "⚠️  INACTIVE"
fi

echo -n "Checking LiteLLM Service... "
if systemctl is-active --quiet podman-litellm.service; then
  echo "✅ Active"
else
  echo "⚠️  INACTIVE"
fi

echo -n "Checking ComfyUI Service... "
if systemctl is-active --quiet podman-comfyui.service; then
  echo "✅ Active"
else
  echo "⚠️  INACTIVE"
fi

echo -n "Checking Langflow Service... "
if systemctl is-active --quiet podman-langflow.service; then
  echo "✅ Active"
else
  echo "⚠️  INACTIVE"
fi

echo -n "Checking Langfuse Service... "
if systemctl is-active --quiet podman-langfuse.service; then
  echo "✅ Active"
else
  echo "⚠️  INACTIVE"
fi

echo -n "Checking Open WebUI Service... "
if systemctl is-active --quiet open-webui.service; then
  echo "✅ Active"
else
  echo "⚠️  INACTIVE (Manual Start)"
fi

# 3. Check Ports (Open WebUI)
echo -n "Checking Open WebUI Port (3000)... " # Updated to port 3000
if timeout 1 bash -c '</dev/tcp/localhost/3000' &>/dev/null; then
  echo "✅ Accessible"
else
  echo "⚠️  Unreachable (Service Inactive)"
fi

# 4. Check Tools existence
echo "Checking Tools:"
REQUIRED_TOOLS=("nh" "fzf" "fastfetch" "mpv" "rg" "starship" "podman")
for tool in "${REQUIRED_TOOLS[@]}"; do
  echo -n "  - $tool... "
  if command -v "$tool" &>/dev/null; then
    echo "✅ Installed"
  else
    echo "❌ MISSING"
  fi
done

echo "🎉 Verification Complete! System is healthy."
