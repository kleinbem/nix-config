#!/usr/bin/env bash
set -e

# Arguments
ROOTFS_TAR="${1:-result/tarball/*.tar.xz}"
ALIAS="${2:-custom-image}"
DESCRIPTION="${3:-NixOS Incus Container}"

echo "🔧 Patching image metadata for '$ALIAS'..."
echo "   - Rootfs: $ROOTFS_TAR"
echo "   - Desc:   $DESCRIPTION"

# Cleanup previous runs
rm -rf tmp/incus-build-temp tmp/image.tar tmp/incus-meta tmp/metadata.tar
mkdir -p tmp/incus-build-temp
mkdir -p tmp/incus-meta

# Dynamically detect architecture (x86_64 or aarch64)
ARCH=$(uname -m)
echo "   - Arch:   $ARCH"

# Create clean metadata
cat > tmp/incus-meta/metadata.yaml <<EOF
{
    "architecture": "$ARCH",
    "creation_date": 1,
    "properties": {
        "description": "$DESCRIPTION",
        "os": "nixos",
        "release": "25.11"
    },
    "templates": {},
    "type": "container"
}
EOF

# Create metadata tarball
tar -C tmp/incus-meta -cf tmp/metadata.tar metadata.yaml

echo "🚀 Importing image (Split Metadata + Rootfs)..."
incus image import tmp/metadata.tar $ROOTFS_TAR --alias "$ALIAS"

# Cleanup
rm -rf tmp/incus-meta tmp/metadata.tar tmp/incus-build-temp

echo "✅ Image '$ALIAS' imported successfully."
