#!/usr/bin/env bash
# Fleet Health Check Script
#
# Audits the kleinbem fleet for common issues and inconsistencies.
# Run periodically (weekly recommended) to catch problems early.
#
# Usage:
#   ./tools/fleet-health-check.sh              # Check all
#   ./tools/fleet-health-check.sh orin-nano    # Check one device
#   ./tools/fleet-health-check.sh --verbose    # Verbose output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERBOSE=${VERBOSE:-0}
TARGET_DEVICE="${1:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}✓${NC} $*"; }
log_fail() { echo -e "${RED}✗${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_info() { echo -e "${BLUE}ℹ${NC} $*"; }

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() { ((PASS_COUNT++)); log_pass "$@"; }
check_fail() { ((FAIL_COUNT++)); log_fail "$@"; }
check_warn() { ((WARN_COUNT++)); log_warn "$@"; }

# ════════════════════════════════════════════════════════════════
# 1. CONFIGURATION CHECKS
# ════════════════════════════════════════════════════════════════

check_config_syntax() {
  echo ""
  echo "Checking NixOS configuration syntax..."

  if nix eval '.#nixosConfigurations.nixos-nvme.config.system.nixos.version' &>/dev/null; then
    check_pass "NixOS config evaluates successfully"
  else
    check_fail "NixOS config has syntax errors"
  fi
}

check_flake_inputs() {
  echo ""
  echo "Checking flake.nix inputs..."

  local inputs=$(nix eval '.#nixosConfigurations.nixos-nvme.config.system.nixos.version' 2>&1 | grep -c "error" || true)

  if [ "$inputs" -eq 0 ]; then
    check_pass "All flake inputs resolve"
  else
    check_warn "Some flake inputs may have issues"
  fi
}

# ════════════════════════════════════════════════════════════════
# 2. INVENTORY CHECKS
# ════════════════════════════════════════════════════════════════

check_inventory() {
  echo ""
  echo "Checking inventory.nix..."

  # Check that all expected devices are defined
  local expected_devices=("nixos-nvme" "core-pi" "mac-mini" "orin-nano" "nasbook" "hass-pi" "phone")
  local missing=0

  for device in "${expected_devices[@]}"; do
    if grep -q "\"$device\"" "$SCRIPT_DIR/inventory.nix"; then
      log_info "Found: $device"
    else
      check_warn "Missing or misspelled: $device"
      ((missing++))
    fi
  done

  if [ $missing -eq 0 ]; then
    check_pass "All expected devices in inventory"
  fi
}

# ════════════════════════════════════════════════════════════════
# 3. DEVICE CHECKS
# ════════════════════════════════════════════════════════════════

check_device() {
  local device=$1
  local ip=$2

  echo ""
  echo "Checking $device (${ip})..."

  # Ping test
  if ping -c 1 -W 2 "$ip" &>/dev/null; then
    check_pass "$device is reachable"

    # SSH test
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "martin@$ip" "echo ok" &>/dev/null 2>&1; then
      check_pass "$device: SSH accessible"

      # NixOS version check
      if ssh -o ConnectTimeout=5 "martin@$ip" "nixos-version" &>/dev/null 2>&1; then
        check_pass "$device: NixOS accessible"
      else
        check_warn "$device: NixOS version check failed"
      fi
    else
      check_warn "$device: SSH not responding"
    fi
  else
    check_warn "$device: Not reachable on LAN"
  fi
}

check_devices() {
  # Parse inventory.nix for active devices
  # This is simplified; in production, you'd parse the Nix file properly

  log_info "Testing LAN connectivity..."

  # If a specific device is requested, check only that one
  if [ -n "$TARGET_DEVICE" ]; then
    case "$TARGET_DEVICE" in
      nixos-nvme) check_device "nixos-nvme" "10.0.0.5" ;;
      core-pi) check_device "core-pi" "10.0.0.22" ;;
      mac-mini) check_device "mac-mini" "10.0.0.16" ;;
      orin-nano) check_device "orin-nano" "10.0.0.15" ;;
      nasbook) check_device "nasbook" "10.0.0.30" ;;
      hass-pi) check_device "hass-pi" "10.0.0.21" ;;
      *) log_warn "Unknown device: $TARGET_DEVICE" ;;
    esac
  else
    # Check all active devices
    check_device "nixos-nvme" "10.0.0.5"
    check_device "core-pi" "10.0.0.22"
    check_device "mac-mini" "10.0.0.16"
    check_device "orin-nano" "10.0.0.15"
    check_device "nasbook" "10.0.0.30"
  fi
}

# ════════════════════════════════════════════════════════════════
# 4. GIT/VERSION CONTROL CHECKS
# ════════════════════════════════════════════════════════════════

check_git_status() {
  echo ""
  echo "Checking git status..."

  if git status >/dev/null 2>&1; then
    local uncommitted=$(git status --short | wc -l)

    if [ "$uncommitted" -eq 0 ]; then
      check_pass "No uncommitted changes"
    else
      check_warn "Uncommitted changes: $uncommitted files"
    fi

    # Check if ahead of origin
    local ahead=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
    if [ "$ahead" -gt 0 ]; then
      check_warn "Commits ahead of origin: $ahead"
    else
      check_pass "In sync with origin"
    fi
  else
    log_info "Not in a git repository"
  fi
}

# ════════════════════════════════════════════════════════════════
# 5. SECRETS CHECKS
# ════════════════════════════════════════════════════════════════

check_secrets() {
  echo ""
  echo "Checking secrets management..."

  # Check for plaintext secrets in repo
  local plaintext=$(find . -name "*.nix" -o -name "*.yaml" | xargs grep -l "password.*=" 2>/dev/null | wc -l || true)

  if [ "$plaintext" -eq 0 ]; then
    check_pass "No plaintext secrets in repo"
  else
    check_warn "Potential plaintext secrets found: $plaintext files"
  fi

  # Check for sops files
  if [ -d "hosts" ]; then
    local sops_files=$(find hosts -name "secrets.yaml" | wc -l || true)
    if [ "$sops_files" -gt 0 ]; then
      check_pass "Found sops secrets: $sops_files files"
    fi
  fi
}

# ════════════════════════════════════════════════════════════════
# 6. DOCUMENTATION CHECKS
# ════════════════════════════════════════════════════════════════

check_documentation() {
  echo ""
  echo "Checking documentation..."

  local docs=(
    "docs/DEVICE-TIERS.md"
    "docs/MODULE-ORGANIZATION.md"
    "docs/TROUBLESHOOTING.md"
    "docs/SECRETS-MANAGEMENT.md"
    "docs/DEPLOYMENT-STRATEGY.md"
    "docs/FLEET-ARCHITECTURE.md"
  )

  for doc in "${docs[@]}"; do
    if [ -f "$SCRIPT_DIR/$doc" ]; then
      check_pass "Found: $doc"
    else
      check_warn "Missing: $doc"
    fi
  done
}

# ════════════════════════════════════════════════════════════════
# 7. MODULE CHECKS
# ════════════════════════════════════════════════════════════════

check_modules() {
  echo ""
  echo "Checking NixOS modules..."

  if [ -d "$SCRIPT_DIR/modules/nixos" ]; then
    local module_count=$(find "$SCRIPT_DIR/modules/nixos" -name "*.nix" | wc -l || true)
    check_pass "Found $module_count NixOS modules"
  fi

  if [ -d "$SCRIPT_DIR/modules/home-manager" ]; then
    local hm_count=$(find "$SCRIPT_DIR/modules/home-manager" -name "*.nix" | wc -l || true)
    check_pass "Found $hm_count Home-Manager modules"
  fi
}

# ════════════════════════════════════════════════════════════════
# 8. SUMMARY
# ════════════════════════════════════════════════════════════════

print_summary() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "HEALTH CHECK SUMMARY"
  echo "═══════════════════════════════════════════════════════════"
  echo -e "Passed:  ${GREEN}${PASS_COUNT}${NC}"
  echo -e "Failed:  ${RED}${FAIL_COUNT}${NC}"
  echo -e "Warned:  ${YELLOW}${WARN_COUNT}${NC}"
  echo ""

  if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}Fleet health: OK${NC}"
  else
    echo -e "${RED}Fleet health: ISSUES DETECTED${NC}"
    echo "See warnings and failures above."
  fi

  echo ""
}

# ════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════

main() {
  echo "╔═════════════════════════════════════════════════════════╗"
  echo "║          Fleet Health Check (2026-08-17)               ║"
  echo "╚═════════════════════════════════════════════════════════╝"

  cd "$SCRIPT_DIR"

  # Run all checks
  check_config_syntax
  check_flake_inputs
  check_inventory
  check_devices
  check_git_status
  check_secrets
  check_documentation
  check_modules

  print_summary

  # Exit with failure if any checks failed
  if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
  fi
}

main "$@"
