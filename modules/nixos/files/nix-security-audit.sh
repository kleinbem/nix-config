#!/usr/bin/env bash
# ==============================================================================
# Unified Security Auditor for NixOS
# ==============================================================================
# Handles: Host Closure (Vulnix/Trivy), Containers, Secrets, and Lynis.
# Supports both background service execution and interactive CLI usage.

set -euo pipefail

# --- Colors ---
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# --- Helpers ---
log_info() { echo -e "${BLUE}info${RESET} [audit] $*"; }
log_warn() { echo -e "${YELLOW}warn${RESET} [audit] $*"; }
log_error() { echo -e "${RED}error${RESET} [audit] $*"; }
log_step() { echo -e "${CYAN}==>${RESET} ${YELLOW}$*${RESET}"; }

# --- Configuration ---
REPORT_DIR="/var/log/security-audit"
if ! mkdir -p "$REPORT_DIR" 2>/dev/null || ! [ -w "$REPORT_DIR" ]; then
  REPORT_DIR="/tmp/security-audit"
  mkdir -p "$REPORT_DIR"
  log_warn "Insufficient permissions for /var/log/security-audit, using $REPORT_DIR"
fi

REPORT_HOST="$REPORT_DIR/security-report-host.txt"
REPORT_CONT="$REPORT_DIR/security-report-containers.txt"
REPORT_SECRETS="$REPORT_DIR/security-report-secrets.json"
REPORT_LYNIS="$REPORT_DIR/lynis-report.txt"
VULNIX_WHITELIST="${VULNIX_WHITELIST:-/etc/nixos/nix-config/modules/nixos/vulnix.whitelist}"
TRIVY_IGNORE="${TRIVY_IGNORE:-/etc/nixos/nix-config/modules/nixos/.trivyignore}"
WORKSPACE_PATH="/home/martin/Develop/github.com/kleinbem/nix"

# Check for required tools
for tool in vulnix trivy gitleaks lynis; do
  if ! command -v "$tool" &>/dev/null; then
    log_error "Required tool '$tool' not found in PATH."
  fi
done

# --- Functions ---

scan_host() {
  log_step "Scanning NixOS Host Closure..."

  # 1. Vulnix (Nix native)
  log_info "Running Vulnix analysis..."
  vulnix --system -w "$VULNIX_WHITELIST" >"$REPORT_HOST" 2>&1 || true

  # 2. Trivy FS (CVE database)
  log_info "Running Trivy Host FS scan..."
  trivy fs /run/current-system \
    --severity HIGH,CRITICAL \
    --ignorefile "$TRIVY_IGNORE" \
    --scanners vuln \
    --format table >>"$REPORT_HOST" 2>&1 || true
}

scan_containers() {
  log_step "Scanning Container Infrastructure..."

  echo "--- Active Podman Images ---" >"$REPORT_CONT"

  # 1. Image Discovery and Scan
  if command -v podman &>/dev/null; then
    log_info "Discovering active Podman images..."
    IMAGES=$(podman images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" || true)

    if [ -n "$IMAGES" ]; then
      for img in $IMAGES; do
        log_info "Scanning image: $img"
        echo -e "\n[IMAGE: $img]" >>"$REPORT_CONT"
        trivy image "$img" \
          --severity HIGH,CRITICAL \
          --ignorefile "$TRIVY_IGNORE" \
          --format table >>"$REPORT_CONT" 2>&1 || true
      done
    else
      log_warn "No Podman images found."
      echo "No images found to scan." >>"$REPORT_CONT"
    fi
  else
    log_error "Podman not found, skipping image scan."
    echo "Error: Podman missing." >>"$REPORT_CONT"
  fi

  # 2. Data Volumes
  log_info "Scanning persistent data volumes (/var/lib/images)..."
  echo -e "\n[VOLUMES: /var/lib/images]" >>"$REPORT_CONT"
  trivy fs /var/lib/images \
    --severity HIGH,CRITICAL \
    --ignorefile "$TRIVY_IGNORE" \
    --scanners vuln \
    --format table >>"$REPORT_CONT" 2>&1 || true
}

scan_secrets() {
  log_step "Scanning Workspace for Secrets..."
  if [ -d "$WORKSPACE_PATH" ]; then
    gitleaks detect \
      --source "$WORKSPACE_PATH" \
      --report-path "$REPORT_SECRETS" \
      --report-format json || true
  else
    log_warn "Workspace path $WORKSPACE_PATH not found, skipping Gitleaks."
  fi
}

scan_lynis() {
  log_step "Running Lynis Infrastructure Audit..."
  # Run audit and capture the full output
  lynis audit system --no-colors >"$REPORT_LYNIS" 2>&1 || true
}

notify_if_needed() {
  # Check if this is running as a service
  if ! [ -t 1 ]; then
    if [ -s "$REPORT_HOST" ] && grep -E "Total: [1-9]|HIGH:|CRITICAL:" "$REPORT_HOST"; then
      systemctl start "security-notify@Security-Risks-Detected|Host-vulnerabilities-found|$REPORT_HOST.service" || true
    fi

    if [ -s "$REPORT_CONT" ] && grep -E "Total: [1-9]|HIGH:|CRITICAL:" "$REPORT_CONT"; then
      systemctl start "security-notify@Container-Vulnerabilities-Found|Risks-detected-in-Podman|$REPORT_CONT.service" || true
    fi
  fi
}

show_summary() {
  log_step "Audit Summary Results"

  # Disable pipefail temporarily to handle 'head' closing pipes on grep
  set +o pipefail

  if [ -f "$REPORT_HOST" ]; then
    echo -e "\n${CYAN}--- Host Vulnerabilities (Nix) ---${RESET}"
    # Check for Vulnix results
    if grep -q "derivations with active advisories" "$REPORT_HOST"; then
      local VULN_COUNT
      VULN_COUNT=$(grep "derivations with active advisories" "$REPORT_HOST" | awk '{print $1}')
      if [[ -n $VULN_COUNT ]] && [[ $VULN_COUNT -gt 0 ]]; then
        echo -e "${RED}Total: $VULN_COUNT nix derivations with advisories${RESET}"
        grep -E "CVE|CVSSv3|https://nvd" "$REPORT_HOST" | head -n 20 || true
      else
        echo -e "${GREEN}Host (Vulnix): No active advisories detected.${RESET}"
      fi
    fi

    # Check for Trivy FS results (if any)
    if grep -q "Total: " "$REPORT_HOST"; then
      echo -e "\n${CYAN}--- Host FS Vulnerabilities (Trivy) ---${RESET}"
      grep -E "Total: |HIGH:|CRITICAL:" "$REPORT_HOST" | tail -n 5 || true
    fi
  fi

  if [ -f "$REPORT_CONT" ]; then
    echo -e "\n${CYAN}--- Container Vulnerabilities ---${RESET}"
    grep -E "Total: |HIGH:|CRITICAL:|\[IMAGE:|\[VOLUMES:" "$REPORT_CONT" | head -n 30 || echo "Containers: No issues detected."
  fi

  if [ -f "$REPORT_SECRETS" ]; then
    echo -e "\n${CYAN}--- Secret Scan ---${RESET}"
    if [ -s "$REPORT_SECRETS" ] && [ "$(jq '. | length' "$REPORT_SECRETS" 2>/dev/null || echo 0)" -gt 0 ]; then
      echo -e "${RED}⚠️  Secrets detected in workspace! Check $REPORT_SECRETS${RESET}"
    else
      echo "No secrets leaked."
    fi
  fi

  # Restore pipefail
  set -o pipefail
}

show_full_logs() {
  log_step "Full Audit Logs"
  for r in "$REPORT_HOST" "$REPORT_CONT" "$REPORT_LYNIS"; do
    if [ -f "$r" ]; then
      echo -e "\n${BLUE}FILE: $r${RESET}"
      echo "--------------------------------------------------------------------------------"
      cat "$r"
      echo "--------------------------------------------------------------------------------"
    fi
  done
}

# --- Main ---

MODE="${1:-all}"

case "$MODE" in
"host") scan_host ;;
"containers") scan_containers ;;
"secrets") scan_secrets ;;
"lynis") scan_lynis ;;
"all")
  scan_host
  scan_containers
  scan_secrets
  scan_lynis
  ;;
*)
  echo "Usage: $0 [all|host|containers|secrets|lynis]"
  exit 1
  ;;
esac

notify_if_needed

if [ -t 1 ]; then
  show_summary
  echo -e "\n${YELLOW}Would you like to see the full logs? (y/N)${RESET}"
  read -r -n 1 -t 10 REPLY || REPLY="n"
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    show_full_logs
  fi
fi

log_step "Security Audit Complete!"
if [ -t 1 ]; then
  echo -e "${GREEN}Full reports preserved in: $REPORT_DIR/security-report-*${RESET}"
fi
