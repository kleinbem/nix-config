#!/usr/bin/env bash
set -e

echo "🔧 Patching image metadata (Extract -> Patch -> Repack)..."
rm -rf tmp/n8n-build-temp tmp/image.tar
mkdir -p tmp/n8n-build-temp

# Dynamically detect architecture (x86_64 or aarch64)
ARCH=$(uname -m)

# Create clean metadata
echo "🔧 Generating metadata for $ARCH..."
mkdir -p tmp/n8n-meta
cat > tmp/n8n-meta/metadata.yaml <<EOF
{
    "architecture": "$ARCH",
    "creation_date": 1,
    "properties": {
        "description": "NixOS n8n Container",
        "os": "nixos",
        "release": "25.11"
    },
    "templates": {},
    "type": "container"
}
EOF

# Create metadata tarball
tar -C tmp/n8n-meta -cf tmp/metadata.tar metadata.yaml

echo "🚀 Importing image (Split Metadata + Rootfs)..."
# $1 is the rootfs tarball (passed from Justfile or found automatically)
ROOTFS_AL="${1:-result/tarball/*.tar.xz}"

incus image import tmp/metadata.tar $ROOTFS_AL --alias n8n-image

# Cleanup
rm -rf tmp/n8n-meta tmp/metadata.tar
