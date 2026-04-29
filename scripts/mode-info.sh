#!/usr/bin/env bash

MODE=$1

# Helper for nice coloring
BOLD='\033[1m'
NC='\033[0m' # No Color
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'

echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "${BOLD}🎭 SYSTEM PROFILE ACTIVATED: ${MODE^^}${NC}"
echo -e "${BLUE}${BOLD}================================================================${NC}"

# 1. CORE SERVICES (Always present)
echo -e "${BOLD}🌍 CORE INFRASTRUCTURE (Always Active)${NC}"
printf "%-25s | %-10s | %-10s | %-20s\n" "Service" "Status" "Auto" "Role"
printf "%-25s | %-10s | %-10s | %-20s\n" "-------------------------" "----------" "----------" "--------------------"
printf "%-25s | %-10s | %-10s | %-20s\n" "Netbird (VPN)" "RUNNING" "YES" "Zero-Trust Mesh"
printf "%-25s | %-10s | %-10s | %-20s\n" "NetworkManager" "RUNNING" "YES" "Connectivity"
printf "%-25s | %-10s | %-10s | %-20s\n" "Snapper / Btrfs" "ACTIVE" "YES" "Data Protection"
printf "%-25s | %-10s | %-10s | %-20s\n" "Sops-Nix" "ACTIVE" "YES" "Secrets Management"
printf "%-25s | %-10s | %-10s | %-20s\n" "Journald" "RUNNING" "YES" "System Logging"
printf "%-25s | %-10s | %-10s | %-20s\n" "Node Exporter" "RUNNING" "YES" "Telemetry"
echo ""

# 2. WORKLOAD SERVICES MATRIX
echo -e "${BOLD}📦 WORKLOAD SERVICES FOR [${MODE^^}]${NC}"
printf "%-25s | %-10s | %-10s | %-20s\n" "Container/Service" "Available" "Activation" "Status/URL"
printf "%-25s | %-10s | %-10s | %-20s\n" "-------------------------" "----------" "----------" "--------------------"

# Function to print a service row
print_row() {
    local name=$1
    local avail=$2
    local active=$3
    local status=$4
    local color=$NC
    if [ "$avail" == "YES" ]; then
        if [ "$active" == "AUTO" ]; then color=$GREEN; else color=$YELLOW; fi
    else
        color=$RED
    fi
    printf "${color}%-25s${NC} | %-10s | %-10s | %-20s\n" "$name" "$avail" "$active" "$status"
}

# Define all services and their status per mode
case $MODE in
    minimal)
        print_row "n8n" "NO" "---" "Disabled"
        print_row "code-server" "NO" "---" "Disabled"
        print_row "authelia" "NO" "---" "Disabled"
        print_row "caddy (Proxy)" "NO" "---" "Disabled"
        print_row "ollama" "NO" "---" "Disabled"
        print_row "open-webui" "NO" "---" "Disabled"
        print_row "comfyui" "NO" "---" "Disabled"
        print_row "langflow" "NO" "---" "Disabled"
        print_row "langfuse" "NO" "---" "Disabled"
        print_row "litellm" "NO" "---" "Disabled"
        print_row "agent-team" "NO" "---" "Disabled"
        print_row "Waydroid" "NO" "---" "Disabled"
        echo -e "\n${GREEN}✔ Minimal Mode: System resources reserved for desktop performance.${NC}"
        ;;
    work)
        print_row "n8n" "YES" "AUTO" "https://n8n.local"
        print_row "code-server" "YES" "AUTO" "https://code.local"
        print_row "authelia" "YES" "AUTO" "Identity Gateway"
        print_row "caddy (Proxy)" "YES" "AUTO" "Reverse Proxy"
        print_row "ollama" "NO" "---" "Disabled"
        print_row "open-webui" "NO" "---" "Disabled"
        print_row "Waydroid" "NO" "---" "Disabled"
        echo -e "\n${GREEN}✔ Work Mode: Productivity and automation stack active.${NC}"
        ;;
    playground)
        print_row "n8n" "YES" "AUTO" "https://n8n.local"
        print_row "code-server" "YES" "AUTO" "https://code.local"
        print_row "authelia" "YES" "AUTO" "Identity Gateway"
        print_row "caddy (Proxy)" "YES" "AUTO" "Reverse Proxy"
        print_row "ollama" "YES" "MANUAL" "AI Backend"
        print_row "open-webui" "YES" "MANUAL" "https://ai.local"
        print_row "comfyui" "YES" "MANUAL" "Image Generation"
        print_row "langflow" "YES" "MANUAL" "AI Workflow"
        print_row "langfuse" "YES" "MANUAL" "Observability"
        print_row "litellm" "YES" "MANUAL" "API Gateway"
        print_row "agent-team" "YES" "MANUAL" "Multi-Agent"
        print_row "Waydroid" "NO" "---" "Disabled"
        echo -e "\n${YELLOW}💡 TIP: Manual services are configured but stopped. Run 'just ai-init-safe' to start.${NC}"
        ;;
    waydroid)
        print_row "Waydroid" "YES" "AUTO" "Android Stack"
        print_row "Android Emulator" "YES" "MANUAL" "Dev Debug"
        print_row "Work Apps" "NO" "---" "Disabled"
        ;;
    work-waydroid)
        print_row "n8n" "YES" "AUTO" "Automation"
        print_row "code-server" "YES" "AUTO" "IDE"
        print_row "Waydroid" "YES" "AUTO" "Android Apps"
        ;;
    hardened)
        print_row "nix-mineral" "YES" "AUTO" "Kernel Hardening"
        print_row "USBGuard" "YES" "AUTO" "USB Lockdown"
        print_row "Printing" "NO" "---" "Disabled"
        print_row "Avahi" "NO" "---" "Disabled"
        ;;
esac

echo -e "${BLUE}================================================================${NC}"
