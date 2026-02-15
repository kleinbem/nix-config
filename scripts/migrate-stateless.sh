#!/usr/bin/env bash

# Mission: Stateless Vault - Identity Migration Script
# Run this BEFORE your first reboot after applying the stateless configuration.

# Set colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🛡️ Starting Identity Migration for Stateless Vault...${NC}"

# Check for sudo
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root (sudo).${NC}"
   exit 1
fi

PERSIST_DIR="/nix/persist"

# 1. Create the persistence subvolume if it's btrfs
echo -e "📂 Preparing persistence layer..."
if [ ! -d "/nix/persist" ]; then
    if [[ $(stat -f -c %T /nix) == "btrfs" ]]; then
        echo -e "✨ Creating Btrfs subvolume ${GREEN}/nix/persist${NC}..."
        btrfs subvolume create /nix/persist
    else
        echo -e "📁 Creating directory ${GREEN}/nix/persist${NC}..."
        mkdir -p /nix/persist
    fi
fi

echo -e "📂 Creating persistence structure in ${PERSIST_DIR}..."
mkdir -p "${PERSIST_DIR}/etc"
mkdir -p "${PERSIST_DIR}/var/lib"
mkdir -p "${PERSIST_DIR}/etc/NetworkManager"

# 2. Migration Function
migrate() {
    src=$1
    dest_parent="${PERSIST_DIR}$(dirname "$src")"
    if [ -e "$src" ]; then
        echo -e "🚚 Migrating ${GREEN}${src}${NC} -> ${PERSIST_DIR}${src}"
        # -a: archive (preserve perms/links), -u: update (only newer), -v: verbose
        cp -au "$src" "$dest_parent"
    else
        echo -e "⚠️  ${YELLOW}${src} not found, skipping.${NC}"
    fi
}

# 3. Perform Migration
migrate "/etc/machine-id"
migrate "/etc/ssh/ssh_host_ed25519_key"
migrate "/etc/ssh/ssh_host_ed25519_key.pub"
migrate "/etc/ssh/ssh_host_rsa_key"
migrate "/etc/ssh/ssh_host_rsa_key.pub"
migrate "/var/lib/tailscale"
migrate "/var/lib/sops"
migrate "/var/lib/NetworkManager"
migrate "/etc/NetworkManager/system-connections"
migrate "/var/lib/bluetooth"
migrate "/var/lib/nixos"
migrate "/var/lib/fprint"
migrate "/var/lib/waydroid"
migrate "/var/lib/incus"
migrate "/var/lib/docker"
migrate "/var/lib/flatpak"
migrate "/var/lib/libvirt"
migrate "/var/lib/cups"
migrate "/var/lib/fwupd"
migrate "/var/db/sudo"
migrate "/etc/cups"
migrate "/etc/waydroid-extra"

echo -e "\n${GREEN}✅ Identity Migration Complete!${NC}"
echo -e "${YELLOW}You can now safely reboot into your Stateless Vault.${NC}"
