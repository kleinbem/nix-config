#!/usr/bin/env bash

# SOURCE OF TRUTH: nix-config/scripts/mode-info.sh
# Dynamic System Profile Info Script - V4.3 (Multi-Profile Support)
# Shows ALL services, their status, and ALL assigned profiles
#
# NOTE: deliberately no `set -e` — every `systemctl` query is allowed to fail
# silently (`2>/dev/null`) because not every host has every service, and the
# fallback logic depends on those failures being non-fatal.

MODE=${1:-minimal}

# Helper for nice coloring
BOLD='\033[1m'
NC='\033[0m' # No Color
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'

echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "${BOLD}🎭 SYSTEM PROFILE ACTIVATED: ${MODE^^}${NC}"
echo -e "${BLUE}${BOLD}================================================================${NC}"

# Profile Color Mapping
get_profile_tags() {
  local name=$1
  local tags=""

  # Check for CORE (Always active)
  case $name in
  netbird | NetworkManager | snapper | sops | journald | node-exporter | cups | caddy | dashboard | virt*)
    tags="${BLUE}CORE${NC}"
    echo -e "$tags"
    return
    ;;
  esac

  # Additive checks
  case $name in
  n8n | code-server | authelia | github-runner)
    tags="${GREEN}WORK${NC}, ${MAGENTA}AI${NC}"
    ;;
  ollama | open-webui | comfyui | langflow | langfuse | litellm | agent-team | agent-zero | qdrant | playground | openclaw | vllm* | falco* | netdata | loki | monitoring)
    tags="${MAGENTA}AI${NC}"
    ;;
  android*)
    tags="${CYAN}SYS${NC}"
    ;;
  *)
    tags="---"
    ;;
  esac
  echo -e "$tags"
}

# 1. CORE INFRASTRUCTURE
echo -e "${BOLD}🌍 CORE INFRASTRUCTURE (Always Active)${NC}"
printf "%-20s | %-10s | %-10s | %-15s | %-20s\n" "Service" "Status" "Auto" "Profile" "Role"
printf "%-20s | %-10s | %-10s | %-15s | %-20s\n" "--------------------" "----------" "----------" "---------------" "--------------------"

check_core() {
  local name=$1
  local unit=$2
  local role=$3
  local status_text="STOPPED"
  local auto="NO"
  local color=$NC

  local active_state
  active_state=$(systemctl show -p ActiveState --value "$unit" 2>/dev/null)
  local sub_state
  sub_state=$(systemctl show -p SubState --value "$unit" 2>/dev/null)
  local result
  result=$(systemctl show -p Result --value "$unit" 2>/dev/null)

  if [[ $active_state == "active" ]]; then
    status_text="RUNNING"
    color=$GREEN
  elif [[ $sub_state == "exited" ]] && [[ $result == "success" ]]; then
    status_text="ACTIVE"
    color=$GREEN
  elif [[ $active_state == "activating" ]]; then
    status_text="STARTING"
    color=$YELLOW
  elif [[ $active_state == "failed" ]]; then
    status_text="FAILED"
    color=$RED
  else
    status_text="STOPPED"
    color=$RED
  fi

  local enabled_state
  enabled_state=$(systemctl is-enabled "$unit" 2>/dev/null)
  if [[ $enabled_state == "enabled" ]] || [[ $enabled_state == "static" ]]; then
    auto="YES"
  else
    auto="NO"
  fi

  local tags
  tags=$(get_profile_tags "$(echo "$name" | awk '{print tolower($1)}' | sed 's/-//g')")
  printf "%-20s | ${color}%-10s${NC} | %-10s | %-24s | %-20s\n" "$name" "$status_text" "$auto" "$tags" "$role"
}

check_core "Netbird (VPN)" "netbird.service" "Zero-Trust Mesh"
check_core "NetworkManager" "NetworkManager.service" "Connectivity"
check_core "Snapper / Btrfs" "snapper-timeline.timer" "Data Protection"
check_core "Sops-Nix" "sops-install-secrets.service" "Secrets Management"
check_core "Journald" "systemd-journald.service" "System Logging"
check_core "Node Exporter" "prometheus-node-exporter.service" "Telemetry"
check_core "CUPS (Printing)" "container@cups.service" "Isolated Container"
check_core "GitHub Runner" "container@github-runner.service" "Isolated Builder"
check_core "Caddy (Proxy)" "container@caddy.service" "Always Active Proxy"
check_core "Dashboard" "container@dashboard.service" "Internal Portal"

echo ""

# 2. WORKLOAD SERVICES MATRIX
echo -e "${BOLD}📦 WORKLOAD SERVICES FOR [${MODE^^}]${NC}"
printf "%-20s | %-10s | %-10s | %-15s | %-20s\n" "Container/Service" "Available" "Activation" "Profile" "Status"
printf "%-20s | %-10s | %-10s | %-15s | %-20s\n" "--------------------" "----------" "----------" "---------------" "--------------------"

UNITS=$( (
  systemctl list-units --type=service --all --no-legend "container@*" "podman-*"
  systemctl list-unit-files --type=service --all --no-legend "container@*" "podman-*"
) |
  awk '{print $1}' | sort -u |
  grep -E "container@.+|podman-.+" |
  grep -vE "@\.service|kube@|cups|github-runner|podman-network-cbr0|auto-update|clean-transient|restart|prune|caddy|dashboard")

# Known services fallback
KNOWN_SERVICES="n8n code-server authelia ollama open-webui comfyui langflow langfuse litellm agent-team agent-zero qdrant monitoring falco netdata loki openclaw playground libvirtd"

for srv in $KNOWN_SERVICES; do
  if ! echo "$UNITS" | grep -q "$srv"; then
    if [ -f "/etc/systemd/system/container@$srv.service" ] || systemctl list-unit-files "container@$srv.service" &>/dev/null; then
      UNITS="$UNITS container@$srv.service"
    elif [ -f "/etc/systemd/system/podman-$srv.service" ] || systemctl list-unit-files "podman-$srv.service" &>/dev/null; then
      UNITS="$UNITS podman-$srv.service"
    elif [ -f "/etc/systemd/system/$srv.service" ] || systemctl list-unit-files "$srv.service" &>/dev/null; then
      UNITS="$UNITS $srv.service"
    fi
  fi
done

UNITS=$(echo "$UNITS" | tr ' ' '\n' | sort -u | grep -v "^$")

for unit in $UNITS; do
  name=$(echo "$unit" | sed -E 's/container@(.*)\.service/\1/; s/podman-(.*)\.service/\1/; s/\.service//')

  avail="YES"
  activation="MANUAL"
  status_text="Stopped"
  color=$NC

  enabled_state=$(systemctl is-enabled "$unit" 2>/dev/null)
  if [[ $enabled_state == "enabled" ]]; then activation="AUTO"; else activation="MANUAL"; fi

  active_state=$(systemctl show -p ActiveState --value "$unit" 2>/dev/null)
  if [[ $active_state == "active" ]]; then
    status_text="RUNNING"
    color=$GREEN
  elif [[ $active_state == "failed" ]]; then
    status_text="FAILED"
    color=$RED
  else
    status_text="Stopped"
    color=$NC
  fi

  tags=$(get_profile_tags "$name")
  printf "${color}%-20s${NC} | %-10s | %-10s | %-24s | %-20s\n" "$name" "$avail" "$activation" "$tags" "$status_text"
done

echo -e "\n${GREEN}✔ ${MODE^^} Mode: Multi-profile fleet state mapped.${NC}"
echo -e "${BLUE}================================================================${NC}"
