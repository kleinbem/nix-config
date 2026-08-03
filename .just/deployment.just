import 'common.just'

set working-directory := ".."

# --- Deployment ---

[group("Fleet")]
deploy-fleet:
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "🚀 Deploying to entire fleet via Colmena..."
    if ! git diff-index --quiet HEAD -- || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        echo "❌ ERROR: Your git tree is dirty!"
        echo "   Colmena evaluates your local dirty tree. Since dirty changes haven't been pushed,"
        echo "   CI hasn't built them, and you will suffer massive local cross-compilation times."
        echo "   Please commit and push your changes (just jj::ship), wait for CI to finish, and try again."
        exit 1
    fi
    
    env SSH_AUTH_SOCK="" colmena -f ./flake.nix apply --impure --show-trace
    just deployment::push-cache all

[group("Fleet")]
[doc("Manually trigger the system.autoUpgrade service on a host to pull the latest production release immediately.")]
update host:
    @echo "🚀 Manually triggering nixos-upgrade.service on {{host}}..."
    @if [ "{{host}}" = "$(hostname)" ]; then \
        sudo systemctl start nixos-upgrade.service; \
    else \
        ssh "{{host}}" "sudo systemctl start nixos-upgrade.service"; \
    fi
    @echo "✅ Upgrade triggered! To watch progress, run:"
    @if [ "{{host}}" = "$(hostname)" ]; then \
        echo "  sudo journalctl -u nixos-upgrade.service -f"; \
    else \
        echo "  ssh {{host}} 'sudo journalctl -u nixos-upgrade.service -f'"; \
    fi

[group("Fleet")]
[doc("Deploy one host by name via Colmena. Nodes: nixos-nvme, orin-nano, core-pi, hass-pi, nasbook. ARM/Pi nodes build on-target and substitute from Attic.")]
deploy host:
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "🚀 Deploying to {{host}} via Colmena..."
    
    # Pre-flight check: Prevent deploying to a node that is booted from an SD card
    if [[ "{{host}}" == "core-pi" || "{{host}}" == "hass-pi" ]]; then
        echo "🔍 Checking boot medium for {{host}}..."
        # We check /nix because / is tmpfs due to impermanence
        if env SSH_AUTH_SOCK="" ssh -o ConnectTimeout=5 "{{host}}" "lsblk -s -n -o NAME \$(findmnt -n -o SOURCE /nix) | grep -q mmcblk0" 2>/dev/null; then
            echo "❌ ERROR: {{host}} is booted from the SD card (/dev/mmcblk0)!"
            echo "   Deploying now would write the bootloader to the SD card, not the SSD."
            echo "   To update the offline SSD, plug it into your laptop and run:"
            echo "       just deployment::pi-update-usb {{host}}"
            echo "   Or, remove the SD card and boot from the SSD before running deploy."
            exit 1
        fi
        echo "✅ Host is booted from the SSD."
    fi

    env SSH_AUTH_SOCK="" colmena -f ./flake.nix apply --impure --on {{host}}
    just deployment::push-cache {{host}}

    # Post-flight sync: Ensure the boot files are fully copied before we report success
    if [[ "{{host}}" == "core-pi" || "{{host}}" == "hass-pi" ]]; then
        echo "⏳ Forcing Raspberry Pi bootloader sync..."
        colmena exec -f ./flake.nix --impure --on "{{host}}" -- systemctl restart sync-rpi-boot.service || echo "⚠️ Warning: Could not force bootloader sync, it may run in the background."
    fi

[group("Fleet")]
deploy-orin:
    @echo "🟢 Deploying to Orin Nano..."
    env SSH_AUTH_SOCK="" colmena -f ./flake.nix apply --impure --on orin-nano
    just deployment::push-cache orin-nano

[group("Provisioning")]
[confirm("💿 Re-install full orin-nano config onto the bootstrapped Orin? Builds natively on the device (no cross-compilation). This reformats the SSD.")]
[doc("Requires bootstrap running and SSH key working. Builds aarch64 closure on the Orin itself, reformats disk with full LUKS+LVM+impermanence layout. LUKS passphrase is prompted interactively.")]
orin-promote host="root@orin-nano-bootstrap.local":
    @echo "🔨 Building and installing full orin-nano config (native aarch64 build on the Orin)..."
    @echo "   LUKS passphrase will be prompted interactively."
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#orin-nano \
        --build-on-remote \
        --phases kexec,disko,install,reboot \
        {{host}}

[group("Provisioning")]
[confirm("💿 Install full orin-nano config skipping kexec? Use this when kexec fails (e.g. Jetson). Target must be reachable and disk not in active use.")]
orin-promote-nokexec host="root@orin-nano-bootstrap.local":
    @echo "🔨 Building and installing full orin-nano config (no kexec — skips RAM boot)..."
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#orin-nano \
        --build-on-remote \
        --phases disko,install,reboot \
        {{host}}

[group("Fleet")]
deploy-edge:
    @echo "📡 Deploying to AI Edge (Orin + Raspberry Pi)..."
    env SSH_AUTH_SOCK="" colmena -f ./flake.nix apply --impure --on orin-nano,core-pi,hass-pi
    just deployment::push-cache orin-nano core-pi hass-pi


[group("Fleet")]
[doc("Push built closure(s) to Attic cache. E.g. 'just deployment::push-cache core-pi' or 'just deployment::push-cache --remote orin-nano'")]
push-cache +args:
    #!/usr/bin/env bash
    set -euo pipefail

    # Attic is a SPARSE OVERLAY on the public caches (see the design note in
    # nix-presets/containers/attic.nix): it must hold ONLY paths no public cache
    # has. attic's own upstream filter covers cache.nixos.org ALONE, so cachix
    # paths (nix-community/devenv/cuda/anduril) leak in. We instead filter every
    # closure member by its on-disk signatures: a path substitutable from any
    # cache this flake trusts carries that cache's signature (key names below
    # mirror trusted-public-keys in nix-config/modules/nixos/core.nix). We push
    # only the unsigned remainder with --no-closure. This is a LOCAL, instant
    # check (no per-path network probe) that keeps Attic small and cuts the RPi5
    # ingest load behind the `os error 110` push timeouts.
    UPSTREAM_KEYS='cache.nixos.org-1 nix-community.cachix.org-1 devenv.cachix.org-1 cuda-maintainers.cachix.org-1 anduril.cachix.org-1'
    push_filtered() {
        local root="$1" label="$2"
        local to_push
        # Emit each closure member whose narinfo has NO signature from an
        # upstream key. Locally-built paths (no sig at all) are pushed too, so
        # Attic is authoritative for exactly what this host runs.
        to_push=$(nix path-info -r --json "$root" 2>/dev/null | jq -r --arg keys "$UPSTREAM_KEYS" '
            ($keys | split(" ")) as $uk
            | to_entries[]
            | select((.value.signatures // []) | any(. as $s | $uk | any(. as $k | ($s | startswith($k + ":")))) | not)
            | .key')
        if [ -z "$to_push" ]; then
            echo "  ✓ $label: fully covered upstream — nothing to push."
            return 0
        fi
        echo "  ☁️ $label: pushing $(printf '%s\n' "$to_push" | wc -l) non-upstream path(s) to Attic..."
        printf '%s\n' "$to_push" | \
            nix run nixpkgs#attic-client -- push --no-closure --stdin system -j 2 \
            || echo "⚠️ Warning: Failed to push $label to Attic"
    }

    IS_REMOTE=0
    HOSTS=()
    for arg in {{args}}; do
        if [ "$arg" = "--remote" ]; then
            IS_REMOTE=1
        else
            HOSTS+=("$arg")
        fi
    done
    
    if [ ${#HOSTS[@]} -eq 0 ]; then
        echo "Usage: push-cache [--remote] <host...>"
        exit 1
    fi

    for h in "${HOSTS[@]}"; do
        if [ "$h" = "all" ]; then
            echo "☁️ Pushing all Colmena nodes to Attic cache..."
            HOSTLIST=$(env SSH_AUTH_SOCK="" colmena -f ./flake.nix eval -E '{ nodes, ... }: builtins.attrNames nodes' 2>/dev/null | tail -n1 | jq -r '.[]')
            for node in $HOSTLIST; do
                echo "  Pushing $node..."
                OUT_PATH=$(nix build .#nixosConfigurations.$node.config.system.build.toplevel --impure --no-link --print-out-paths 2>/dev/null)
                push_filtered "$OUT_PATH" "$node"
            done
        else
            echo "☁️ Pushing $h to Attic cache..."
            OUT_PATH=$(nix eval .#nixosConfigurations.$h.config.system.build.toplevel --impure --raw 2>/dev/null || true)
            if [ -z "$OUT_PATH" ]; then
                echo "⚠️ Warning: Could not evaluate closure path for $h"
                continue
            fi
            
            if [ "$IS_REMOTE" -eq 1 ]; then
                echo "  Fetching closure from remote $h (nix copy)..."
                nix copy --from "ssh://$h" "$OUT_PATH" || echo "⚠️ Warning: Failed to fetch closure from $h"
            else
                # Ensure it is realized locally if not remote
                nix build .#nixosConfigurations.$h.config.system.build.toplevel --impure --no-link >/dev/null 2>&1 || true
            fi

            push_filtered "$OUT_PATH" "$h"
        fi
    done
    echo "✅ Cache push complete."

# Note: SSH-based diagnostic recipes (ping/tegrastats/logs/shell) live in
# `orin.just` alongside the on-device ones. Run `just --list orin` to see them.

# INERT as of 2026-07-23 — do not run. This Jetson exposes no /dev/tpm0 (see
# hosts/orin-nano/disko.nix: tpm2-device was removed from the LUKS config), so
# the tpm2_pcrseal below has no device to seal against. Nothing consumes the
# output either, and the path is wrong (Orin persist is /nix/persist, not
# /persist). LUKS unlock is FIDO2 + Tang/clevis. Kept as a placeholder for if
# TPM sealing is ever wired up (hardware.nix does load the tpm_crb module).
[group("Provisioning")]
[confirm("🔐 Seal the TPM key on the Orin Nano? This can only be done once after boot.")]
orin-seal:
    @echo "🔐 Sealing Orin Nano TPM keys..."
    @ssh root@orin-nano.local "tpm2_pcrseal -g sha256 -l 7 -o /persist/tpm-seal.bin"

[group("Provisioning")]
[confirm("🟢 Install minimal NixOS bootstrap onto USB SSD for Orin Nano? This is destructive.")]
orin-install-bootstrap device="/dev/sdb":
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Prompt for sudo upfront and keep it alive in the background
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    echo "🔍 Ensuring clean state before install..."
    sudo umount -R /mnt/orin-bootstrap 2>/dev/null || true
    sudo vgchange -an vg_orin 2>/dev/null || true
    disk_name=$(basename {{device}})
    for part in /sys/class/block/${disk_name}*/holders/*; do
        [ -e "$part" ] && sudo cryptsetup close "$(basename "$(readlink "$part")")" 2>/dev/null || true
    done
    sudo cryptsetup close orin_crypt 2>/dev/null || true
    echo "💿 Wiping {{device}}..."
    sudo dd if=/dev/zero of={{device}} bs=1M count=1200 status=none
    sudo wipefs -a {{device}} 2>/dev/null || true
    for part in $(ls {{device}}* 2>/dev/null | grep -v "^{{device}}$"); do
        sudo wipefs -a "$part" 2>/dev/null || true
    done
    sudo partprobe {{device}} 2>/dev/null || true
    echo "🗂️  Partitioning and formatting via disko..."
    sudo nix run github:nix-community/disko -- --mode destroy,format,mount --argstr device {{device}} --root-mountpoint /mnt/orin-bootstrap ./hosts/orin-nano-bootstrap/disko.nix
    echo "🔨 Building aarch64 closure (sandbox disabled for QEMU JIT, skipping offline remote builder)..."
    # nixos-install does not forward --option to its internal nix build, so we pre-build here
    # where sandbox=false and builders="" are honoured, then hand the result to --system.
    nix build .#nixosConfigurations.orin-nano-bootstrap.config.system.build.toplevel \
        --option sandbox false \
        --option builders "" \
        {{OVERRIDES}} \
        --out-link /tmp/orin-bootstrap-system
    echo "🏗️  Installing bootstrap NixOS closure (skipping bootloader — installed manually below)..."
    # --no-bootloader: nixos-install's bootloader step chroots into aarch64 binaries via QEMU,
    # but QEMU's uname() returns x86_64, causing bootctl to bail with exit 255.
    # All bootloader files are just static copies; we do them from the host side instead.
    sudo nixos-install --root /mnt/orin-bootstrap --system "$(readlink /tmp/orin-bootstrap-system)" --no-root-passwd --no-bootloader

    echo "💾 Installing systemd-boot to ESP (host-side, no aarch64 execution required)..."
    SYSTEM="$(readlink /tmp/orin-bootstrap-system)"
    ESP="/mnt/orin-bootstrap/boot"

    BOOT_EFI="$(find /mnt/orin-bootstrap/nix/store -maxdepth 6 -name "systemd-bootaa64.efi" 2>/dev/null | head -1)"
    [ -n "$BOOT_EFI" ] || { echo "❌ systemd-bootaa64.efi not found in store" >&2; exit 1; }

    KERNEL_SRC="$(realpath "${SYSTEM}/kernel")"
    INITRD_SRC="$(realpath "${SYSTEM}/initrd")"
    KERNEL_PARAMS="$(cat "${SYSTEM}/kernel-params")"
    SYS_STORE_PATH="/nix/store/$(basename "${SYSTEM}")"

    sudo mkdir -p "${ESP}/EFI/systemd" "${ESP}/EFI/BOOT" "${ESP}/EFI/nixos" "${ESP}/loader/entries"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/systemd/systemd-bootaa64.efi"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/BOOT/BOOTAA64.EFI"
    sudo cp "${KERNEL_SRC}" "${ESP}/EFI/nixos/kernel"
    sudo cp "${INITRD_SRC}" "${ESP}/EFI/nixos/initrd"

    printf 'timeout 5\ndefault nixos-1.conf\neditor no\n' | sudo tee "${ESP}/loader/loader.conf" > /dev/null

    ENTRY="$(mktemp)"
    printf 'title NixOS Bootstrap\nlinux /EFI/nixos/kernel\ninitrd /EFI/nixos/initrd\noptions init=%s/init %s\n' \
        "${SYS_STORE_PATH}" "${KERNEL_PARAMS}" > "${ENTRY}"
    sudo cp "${ENTRY}" "${ESP}/loader/entries/nixos-1.conf"
    rm "${ENTRY}"

    rm -f /tmp/orin-bootstrap-system
    echo "🔌 Cleaning up..."
    sudo umount -R /mnt/orin-bootstrap || true
    echo "✅ Bootstrap done! Plug the SSD into the Orin, boot it, then run: just deployment::orin-promote"

[group("Provisioning")]
[confirm("💿 WIPE the USB SSD and install NixOS for Orin Nano? This is destructive.")]
orin-install-usb device="/dev/sdb":
    #!/usr/bin/env bash
    set -euo pipefail
    source .just/lib/provision-common.sh

    DEV="{{device}}"; MNT="/mnt/orin"; CRYPT="orin_crypt"; VG="vg_orin"
    pc_sudo_keepalive
    pc_require_block_device "$DEV"
    pc_assert_safe_target "$DEV"
    # jetpack/l4t + the tegra kernel are large and not always in Attic; allow those
    # to build locally but still catch an unexpected miss (PC_ALLOW_BUILD=1 skips).
    # Dry-run WITH the overrides so it evaluates the closure we actually build.
    pc_cache_preflight orin-nano 'l4t-.*|.*-tegra.*|.*-jetson.*|.*[Oo]rin.*' {{OVERRIDES}}

    _run_disko() {
        sudo nix run github:nix-community/disko -- \
            --mode destroy,format,mount \
            --argstr device "$DEV" --arg secondDiskDevice null \
            --root-mountpoint "$MNT" ./hosts/orin-nano/disko.nix
    }

    echo "🔍 Ensuring clean state before install..."
    pc_cleanup "$MNT" "$DEV" "$CRYPT" "$VG"
    pc_wipe "$DEV" 1200

    # disko can fail on USB-NVMe enclosures two recoverable ways: (1) a 0-sector
    # dm-crypt when the --persistent luksOpen writeback races UAS re-enumeration;
    # (2) a stale /dev/vg_orin node from a prior auto-activation. Clean + one retry.
    if ! _run_disko; then
        crypt_size=$(sudo blockdev --getsize64 /dev/mapper/orin_crypt 2>/dev/null || echo 0)
        if [ "$crypt_size" = "0" ]; then
            echo "🔄 disko failed: 0-sector dm-crypt (USB re-enumeration race)."
        elif [ -d /dev/vg_orin ] && ! sudo vgdisplay vg_orin >/dev/null 2>&1; then
            echo "🔄 disko failed: stale /dev/vg_orin node (udev leftover)."
        else
            echo "❌ disko failed for an unrecognized reason (orin_crypt size: ${crypt_size}). Aborting."; exit 1
        fi
        echo "🔄 Retrying disko from scratch..."
        pc_cleanup "$MNT" "$DEV" "$CRYPT" "$VG"; pc_wipe "$DEV" 1200
        if ! _run_disko; then
            echo "❌ disko failed again — manual intervention needed."
            echo "   Try: sudo cryptsetup close orin_crypt; sudo rm -rf /dev/vg_orin; sudo udevadm settle"; exit 1
        fi
    fi

    # Guard: /mnt/orin/boot MUST be the target's ESP, not the workstation's.
    pc_assert_esp_on_target "$MNT" "$DEV"

    SYSTEM="$(pc_build_toplevel orin-nano {{OVERRIDES}})"
    [ -n "$SYSTEM" ] && [ -e "$SYSTEM" ] || { echo "❌ orin-nano closure build failed."; exit 1; }
    pc_install_closure "$MNT" "$SYSTEM"

    echo "💾 Installing systemd-boot to the ESP (host-side; bootctl can't run under QEMU)..."
    pc_assert_esp_on_target "$MNT" "$DEV"   # re-verify right before writing
    ESP="$MNT/boot"
    BOOT_EFI="$(find "$MNT/nix/store" -maxdepth 6 -name systemd-bootaa64.efi 2>/dev/null | head -1)"
    [ -n "$BOOT_EFI" ] || { echo "❌ systemd-bootaa64.efi not found in store" >&2; exit 1; }
    KERNEL_SRC="$(realpath "${SYSTEM}/kernel")"
    INITRD_SRC="$(realpath "${SYSTEM}/initrd")"
    KERNEL_PARAMS="$(cat "${SYSTEM}/kernel-params")"
    SYS_STORE_PATH="/nix/store/$(basename "${SYSTEM}")"
    sudo mkdir -p "${ESP}/EFI/systemd" "${ESP}/EFI/BOOT" "${ESP}/EFI/nixos" "${ESP}/loader/entries"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/systemd/systemd-bootaa64.efi"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/BOOT/BOOTAA64.EFI"
    sudo cp "${KERNEL_SRC}" "${ESP}/EFI/nixos/kernel"
    sudo cp "${INITRD_SRC}" "${ESP}/EFI/nixos/initrd"
    # CRITICAL: embed boot.initrd.secrets (clevis JWE + initrd-sshd host key) into
    # the ESP initrd. nixos-install --no-bootloader skipped this; without it the
    # first boot fails copy-secrets + sshd and drops to EMERGENCY MODE.
    pc_append_initrd_secrets orin-nano "${ESP}/EFI/nixos/initrd" {{OVERRIDES}}
    printf 'timeout 5\ndefault nixos-1.conf\neditor no\n' | sudo tee "${ESP}/loader/loader.conf" > /dev/null
    ENTRY="$(mktemp)"
    printf 'title NixOS\nlinux /EFI/nixos/kernel\ninitrd /EFI/nixos/initrd\noptions init=%s/init %s\n' \
        "${SYS_STORE_PATH}" "${KERNEL_PARAMS}" > "${ENTRY}"
    sudo cp "${ENTRY}" "${ESP}/loader/entries/nixos-1.conf"; rm "${ENTRY}"
    rm -f /tmp/orin-nano-system

    AGE_PUB="$(pc_host_identity "$MNT" orin-nano)"
    echo "📋 orin-nano age public key: ${AGE_PUB}"
    pc_sops_add_and_reencrypt "$AGE_PUB" orin-nano

    pc_clevis_bind_tang "$CRYPT"

    pc_teardown "$MNT" "$CRYPT" "$VG"
    echo ""
    echo "✅ Orin Nano SSD installation complete!"
    echo "   1. Commit secrets + config:  just jj::save-all 'feat: orin-nano install'"
    echo "   2. Plug SSD into the Jetson, connect ethernet, and boot"
    echo "   3. Load the re-encrypted secrets onto the running host:"
    echo "        just deployment::deploy-orin   (colmena apply — the installed"
    echo "        closure predates the sops re-encryption, so its runtime secrets"
    echo "        won't decrypt until this first deploy rebuilds against them)"

[group("Provisioning")]
[confirm("🔄 Re-install orin-nano config to an ALREADY-PROVISIONED SSD in the USB reader (NO wipe)? Mounts the existing LUKS/LVM, rebuilds, and refreshes the closure + bootloader.")]
[doc("Non-destructive in-place update of an installed Orin SSD. Mounts the existing disk via disko (prompts for the LUKS passphrase), rebuilds the closure with local overrides, reinstalls it, and re-writes systemd-boot host-side. Use after config changes (e.g. clevis/disko tweaks) without re-wiping or re-copying from scratch.")]
orin-update-usb device="/dev/sdb":
    #!/usr/bin/env bash
    set -euo pipefail
    source .just/lib/provision-common.sh

    # Prompt for sudo upfront and keep it alive in the background
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

    echo "🔓 Mounting existing SSD via disko (enter the Orin LUKS passphrase when prompted)..."
    sudo nix run github:nix-community/disko -- \
        --mode mount \
        --argstr device {{device}} \
        --arg secondDiskDevice null \
        --root-mountpoint /mnt/orin \
        ./hosts/orin-nano/disko.nix

    echo "🏗️ Building orin-nano closure..."
    nix build .#nixosConfigurations.orin-nano.config.system.build.toplevel \
        --option sandbox false \
        --option builders "" \
        {{OVERRIDES}} \
        --out-link /tmp/orin-system

    SYSTEM="$(readlink /tmp/orin-system)"
    ESP="/mnt/orin/boot"

    echo "💿 Installing closure (skipping bootloader — done host-side below)..."
    sudo nixos-install --root /mnt/orin --system "${SYSTEM}" --no-root-passwd --no-bootloader

    echo "💾 Installing systemd-boot to ESP (host-side, no aarch64 execution)..."
    BOOT_EFI="$(find /mnt/orin/nix/store -maxdepth 6 -name "systemd-bootaa64.efi" 2>/dev/null | head -1)"
    [ -n "$BOOT_EFI" ] || { echo "❌ systemd-bootaa64.efi not found in store" >&2; exit 1; }
    sudo mkdir -p "${ESP}/EFI/systemd" "${ESP}/EFI/BOOT" "${ESP}/EFI/nixos" "${ESP}/loader/entries"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/systemd/systemd-bootaa64.efi"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/BOOT/BOOTAA64.EFI"
    sudo cp "$(realpath "${SYSTEM}/kernel")" "${ESP}/EFI/nixos/kernel"
    sudo cp "$(realpath "${SYSTEM}/initrd")" "${ESP}/EFI/nixos/initrd"
    # CRITICAL: embed boot.initrd.secrets or the boot drops to emergency mode.
    pc_append_initrd_secrets orin-nano "${ESP}/EFI/nixos/initrd" {{OVERRIDES}}
    printf 'timeout 5\ndefault nixos-1.conf\neditor no\n' | sudo tee "${ESP}/loader/loader.conf" > /dev/null
    ENTRY="$(mktemp)"
    printf 'title NixOS\nlinux /EFI/nixos/kernel\ninitrd /EFI/nixos/initrd\noptions init=%s/init %s\n' \
        "/nix/store/$(basename "${SYSTEM}")" "$(cat "${SYSTEM}/kernel-params")" > "${ENTRY}"
    sudo cp "${ENTRY}" "${ESP}/loader/entries/nixos-1.conf"
    rm "${ENTRY}"
    rm -f /tmp/orin-system

    pc_teardown /mnt/orin orin_crypt vg_orin
    echo "✅ In-place update complete — put the SSD in the Orin, plug in ethernet, and boot."


[group("Provisioning")]
[doc("Generate/rotate a host's Tang-wrapped LUKS unlock secret (nix-secrets/initrd/cryptroot_<host>.jwe), consumed by my.boot.clevis-initrd.secretFile. Prompts for the LUKS passphrase — must match what's actually set on that host's LUKS container, or the JWE decrypts to the wrong passphrase and auto-unlock fails.")]
generate-jwe host:
    @bash scripts/generate-jwe.sh {{host}}

[group("Provisioning")]
[confirm("💿 WIPE the USB-attached SSD and install NixOS for mac-mini? This is destructive. A random LUKS passphrase will be generated and printed at the end for you to save.")]
[doc("mac-mini has ZERO physical peripherals (no keyboard/screen, ever). Fully non-interactive: generates a random passphrase, formats, builds, and Tang-binds in one pass — no generate-jwe.sh/mac-mini-update-usb dance needed. See the final output for what's still manual (NetBird cleanup, physically plugging in the SSD, saving the passphrase).")]
mac-mini-install-usb device="/dev/sdb":
    #!/usr/bin/env bash
    set -euo pipefail
    source .just/lib/provision-common.sh

    DEV="{{device}}"; MNT="/mnt/mac-mini"; CRYPT="mac_mini_crypt"
    pc_sudo_keepalive
    pc_require_block_device "$DEV"
    pc_assert_safe_target "$DEV"
    # No cache pre-flight here on purpose: mac-mini is x86_64, same arch as
    # this workstation, so a local build is a normal fast native build, not
    # an hours-long QEMU-emulated cross-arch one (the thing pc_cache_preflight
    # exists to catch). It's also a brand-new host with nothing in Attic yet.

    # Random alnum passphrase, not human-chosen: this box has no console to
    # ever type it at again in normal operation (Tang auto-unlock is the real
    # unlock path) — 14 chars (~83 bits of alnum entropy) is still far beyond
    # brute-force reach for a passphrase this rarely used, and short enough to
    # type by hand for the one legitimate reason to ever need it: the
    # initrd-SSH fallback if Tang is ever unreachable at boot. Also avoids the
    # old real risk of a mismatch between the disko-format-time and
    # generate-jwe-time passphrase from manual entry. Save it to Bitwarden per
    # the printed output — this script does NOT persist it anywhere itself.
    # NOT `tr ... | head -c 14`: head closes the pipe after 14 bytes, tr gets
    # SIGPIPE writing into it, and under this script's `set -o pipefail` that
    # aborts the whole recipe (exit 141) despite the passphrase itself being
    # fine. Read a generous fixed amount up front instead (tr fully consumes
    # it, no pipe closes early) and slice with bash, no second pipe at all.
    RAW_ENTROPY="$(head -c 256 /dev/urandom | tr -dc 'A-Za-z0-9')"
    if [ "${#RAW_ENTROPY}" -lt 14 ]; then
      echo "❌ Only got ${#RAW_ENTROPY} alnum chars from 256 random bytes (need 14) — vanishingly unlikely, just retry."
      exit 1
    fi
    PASSPHRASE="${RAW_ENTROPY:0:14}"
    PASS_FILE="$(mktemp)"
    chmod 600 "$PASS_FILE"
    printf '%s' "$PASSPHRASE" > "$PASS_FILE"
    # Belt-and-suspenders: wipe the passphrase from this script's memory and
    # the temp file on ANY exit path (success, error, or Ctrl-C), not just
    # the happy path at the bottom.
    cleanup_passfile() { shred -u "$PASS_FILE" 2>/dev/null || rm -f "$PASS_FILE"; }
    trap cleanup_passfile EXIT

    echo "🔍 Ensuring clean state before install..."
    pc_cleanup "$MNT" "$DEV" "$CRYPT" ""
    pc_wipe "$DEV" 100

    # Generate the Tang JWE BEFORE formatting, using the passphrase we just
    # chose ourselves — no need to wait until after disko like the old
    # (manual-passphrase) flow did, since we already know the exact value.
    # git add makes the new file visible to the git+file:// override
    # {{OVERRIDES}} uses to resolve inputs.nix-secrets to this local checkout
    # (Nix flakes only see tracked/staged files, not arbitrary untracked
    # ones) — jj::save-all later gives it a real commit message, this just
    # gets it build-visible right now.
    echo "🔑 Generating Tang JWE with the new passphrase..."
    LUKS_PASSPHRASE="$PASSPHRASE" ./scripts/generate-jwe.sh mac-mini
    git -C ../nix-secrets add initrd/cryptroot_mac-mini.jwe

    echo "💽 Formatting via disko (non-interactive — passphrase generated above)..."
    sudo nix run github:nix-community/disko -- \
        --mode destroy,format,mount \
        --argstr device "$DEV" \
        --argstr passwordFile "$PASS_FILE" \
        --root-mountpoint "$MNT" ./hosts/mac-mini/disko.nix

    # Guard: /mnt/mac-mini/boot MUST be the target's ESP, not the workstation's.
    pc_assert_esp_on_target "$MNT" "$DEV"

    # my.boot.clevis-initrd.enable is gated on the JWE existing (see
    # hosts/mac-mini/default.nix) — it already does now, so this one build
    # comes out clevis-enabled from the start; no second pass required.
    SYSTEM="$(pc_build_toplevel mac-mini {{OVERRIDES}})"
    [ -n "$SYSTEM" ] && [ -e "$SYSTEM" ] || { echo "❌ mac-mini closure build failed."; exit 1; }
    pc_install_closure "$MNT" "$SYSTEM"

    echo "💾 Installing systemd-boot to the ESP (host-side; writing NVRAM boot vars here would register against THIS workstation's EFI, not mac-mini's)..."
    pc_assert_esp_on_target "$MNT" "$DEV"   # re-verify right before writing
    ESP="$MNT/boot"
    BOOT_EFI="$(find "$MNT/nix/store" -maxdepth 6 -name systemd-bootx64.efi 2>/dev/null | head -1)"
    [ -n "$BOOT_EFI" ] || { echo "❌ systemd-bootx64.efi not found in store" >&2; exit 1; }
    KERNEL_SRC="$(realpath "${SYSTEM}/kernel")"
    INITRD_SRC="$(realpath "${SYSTEM}/initrd")"
    KERNEL_PARAMS="$(cat "${SYSTEM}/kernel-params")"
    SYS_STORE_PATH="/nix/store/$(basename "${SYSTEM}")"
    sudo mkdir -p "${ESP}/EFI/systemd" "${ESP}/EFI/BOOT" "${ESP}/EFI/nixos" "${ESP}/loader/entries"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/systemd/systemd-bootx64.efi"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/BOOT/BOOTX64.EFI"
    sudo cp "${KERNEL_SRC}" "${ESP}/EFI/nixos/kernel"
    sudo cp "${INITRD_SRC}" "${ESP}/EFI/nixos/initrd"
    # CRITICAL: embed boot.initrd.secrets (initrd-sshd host key + the clevis
    # JWE, both already present now) into the ESP initrd. nixos-install
    # --no-bootloader skipped this; without it the first boot fails
    # copy-secrets + sshd and drops to EMERGENCY MODE (which, with no
    # physical keyboard attached, is unrecoverable without re-plugging the
    # SSD into this workstation).
    pc_append_initrd_secrets mac-mini "${ESP}/EFI/nixos/initrd" {{OVERRIDES}}
    printf 'timeout 5\ndefault nixos-1.conf\neditor no\n' | sudo tee "${ESP}/loader/loader.conf" > /dev/null
    ENTRY="$(mktemp)"
    printf 'title NixOS\nlinux /EFI/nixos/kernel\ninitrd /EFI/nixos/initrd\noptions init=%s/init %s\n' \
        "${SYS_STORE_PATH}" "${KERNEL_PARAMS}" > "${ENTRY}"
    sudo cp "${ENTRY}" "${ESP}/loader/entries/nixos-1.conf"; rm "${ENTRY}"
    rm -f /tmp/mac-mini-system

    AGE_PUB="$(pc_host_identity "$MNT" mac-mini)"
    echo "📋 mac-mini age public key: ${AGE_PUB}"
    pc_sops_add_and_reencrypt "$AGE_PUB" mac-mini

    pc_clevis_bind_tang "$CRYPT" "$PASS_FILE"

    pc_teardown "$MNT" "$CRYPT"
    echo ""
    echo "✅ mac-mini SSD install complete (JWE generated, disk formatted, closure"
    echo "   built + installed, Tang-bound — all in this one pass). Remaining steps"
    echo "   are the ones that genuinely can't be scripted (secrets need a real"
    echo "   commit message, the disk needs a human hand to move it):"
    echo ""
    echo "   1. just jj::save-all 'feat: mac-mini reinstall' mac-mini nix-secrets"
    echo "        (the JWE was already 'git add'-ed above so the build could see"
    echo "        it — this gives it a proper commit through jj)"
    echo "   2. (cd ../nix/infra/netbird && just remove-peer mac-mini)   (clears"
    echo "        the OLD peer identity from the wiped host BEFORE it re-enrolls"
    echo "        under the same name; skip if this is a first-ever install, not"
    echo "        a reinstall. Standalone Justfile — run from its own dir, no"
    echo "        fleet-wide 'just in' passthrough for it)"
    echo "   3. THEN plug the SSD into the Mac Mini, connect ethernet, and boot"
    echo "   4. just deployment::mac-mini-verify   (once it's reachable over SSH —"
    echo "        confirms auto-unlock, static IP, NetBird, and the sway/wayvnc"
    echo "        remote desktop all actually came up clean)"
    echo ""
    echo "🔑 LUKS passphrase for mac-mini (save to Bitwarden now, then close this"
    echo "   terminal — it is NOT stored anywhere by this script):"
    echo ""
    echo "   ${PASSPHRASE}"
    echo ""

[group("Provisioning")]
[confirm("🔄 Re-install mac-mini config to an ALREADY-PROVISIONED SSD in the USB reader (NO wipe)? Mounts the existing LUKS, rebuilds, and refreshes the closure + bootloader.")]
[doc("Non-destructive in-place update. Also the required second step after generate-jwe.sh — see mac-mini-install-usb's final output.")]
mac-mini-update-usb device="/dev/sdb":
    #!/usr/bin/env bash
    set -euo pipefail
    source .just/lib/provision-common.sh

    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

    echo "🔓 Mounting existing SSD via disko (enter the mac-mini LUKS passphrase when prompted)..."
    sudo nix run github:nix-community/disko -- \
        --mode mount \
        --argstr device {{device}} \
        --root-mountpoint /mnt/mac-mini \
        ./hosts/mac-mini/disko.nix

    echo "🏗️ Building mac-mini closure..."
    nix build .#nixosConfigurations.mac-mini.config.system.build.toplevel \
        --option sandbox false \
        --option builders "" \
        {{OVERRIDES}} \
        --out-link /tmp/mac-mini-system

    SYSTEM="$(readlink /tmp/mac-mini-system)"
    ESP="/mnt/mac-mini/boot"

    echo "💿 Installing closure (skipping bootloader — done host-side below)..."
    sudo nixos-install --root /mnt/mac-mini --system "${SYSTEM}" --no-root-passwd --no-bootloader

    echo "💾 Installing systemd-boot to ESP (host-side)..."
    BOOT_EFI="$(find /mnt/mac-mini/nix/store -maxdepth 6 -name "systemd-bootx64.efi" 2>/dev/null | head -1)"
    [ -n "$BOOT_EFI" ] || { echo "❌ systemd-bootx64.efi not found in store" >&2; exit 1; }
    sudo mkdir -p "${ESP}/EFI/systemd" "${ESP}/EFI/BOOT" "${ESP}/EFI/nixos" "${ESP}/loader/entries"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/systemd/systemd-bootx64.efi"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/BOOT/BOOTX64.EFI"
    sudo cp "$(realpath "${SYSTEM}/kernel")" "${ESP}/EFI/nixos/kernel"
    sudo cp "$(realpath "${SYSTEM}/initrd")" "${ESP}/EFI/nixos/initrd"
    # CRITICAL: embed boot.initrd.secrets or the boot drops to emergency mode.
    pc_append_initrd_secrets mac-mini "${ESP}/EFI/nixos/initrd" {{OVERRIDES}}
    printf 'timeout 5\ndefault nixos-1.conf\neditor no\n' | sudo tee "${ESP}/loader/loader.conf" > /dev/null
    ENTRY="$(mktemp)"
    printf 'title NixOS\nlinux /EFI/nixos/kernel\ninitrd /EFI/nixos/initrd\noptions init=%s/init %s\n' \
        "/nix/store/$(basename "${SYSTEM}")" "$(cat "${SYSTEM}/kernel-params")" > "${ENTRY}"
    sudo cp "${ENTRY}" "${ESP}/loader/entries/nixos-1.conf"
    rm "${ENTRY}"
    rm -f /tmp/mac-mini-system

    pc_teardown /mnt/mac-mini mac_mini_crypt
    echo "✅ In-place update complete — put the SSD in the Mac Mini, plug in ethernet, and boot."

[group("Provisioning")]
[doc("Post-boot sanity check after a mac-mini (re)install: SSH reachability, static IP, tg3 in the running kernel, NetBird mesh status, and the sway/wayvnc remote-desktop services. Read-only — doesn't change anything.")]
mac-mini-verify ip="10.0.0.16":
    #!/usr/bin/env bash
    set -uo pipefail
    IP="{{ip}}"
    fail=0
    check() { echo -n "  $1... "; }
    ok() { echo "✅ $1"; }
    bad() { echo "❌ $1"; fail=1; }

    # This YubiKey's SSH credential requires PIN entry, not just touch (see
    # hosts/nixos-nvme/ssh-fido-recovery.nix) — that PIN has to go through the
    # terminal, not a GUI askpass dialog which doesn't work headlessly/in a
    # script. A `just` recipe's shebang script is a non-interactive bash
    # process, so shellAliases.ssh (which normally sets this) never applies
    # here — set it explicitly instead. BatchMode=yes would silently disable
    # the PIN prompt entirely and fail closed, so it's deliberately not used
    # for the first connection.
    export SSH_ASKPASS_REQUIRE=never

    check "SSH reachable"
    if ssh -o ConnectTimeout=15 "$IP" true; then ok "reachable"; else bad "unreachable — stopping"; exit 1; fi

    check "auto-unlock (no physical passphrase needed to reach here)"
    ok "implied by SSH reachability — this host has no console fallback"

    check "static IP bound to enp2s0f0"
    if ssh "$IP" "ip -4 addr show enp2s0f0" 2>/dev/null | grep -q "$IP/"; then ok "$IP bound"; else bad "expected $IP not found on enp2s0f0"; fi

    check "tg3 loaded (initrd NIC driver made it into the running kernel too)"
    if ssh "$IP" "lsmod | grep -q '^tg3'" 2>/dev/null; then ok "tg3 loaded"; else bad "tg3 not loaded"; fi

    nb="$(ssh "$IP" "netbird status" 2>/dev/null || true)"
    check "NetBird management connection"
    if echo "$nb" | grep -q "Management: Connected"; then ok "connected"; else bad "not connected"; fi
    check "NetBird visible peers"
    if echo "$nb" | grep -qE "Peers count: [1-9]"; then ok "has visible peers"; else bad "0 peers — check groups.tf membership / default-policy closure"; fi

    check "sway-headless + wayvnc services"
    st="$(ssh "$IP" "systemctl is-active sway-headless.service wayvnc.service" 2>/dev/null || true)"
    active_count="$(echo "$st" | grep -c '^active$')"
    if [ "$active_count" = "2" ]; then ok "both active"; else bad "not both active: $st"; fi

    check "wayvnc listening on loopback only (127.0.0.1:5900, not exposed)"
    if ssh "$IP" "ss -tlnp 2>/dev/null | grep -q '127.0.0.1:5900'" 2>/dev/null; then ok "loopback-only, as designed"; else bad "not listening where expected"; fi

    echo ""
    if [ "$fail" = "0" ]; then echo "✅ All checks passed."; else echo "❌ Some checks failed — see above."; exit 1; fi

[group("Provisioning")]
[confirm("💿 WIPE the USB SSD and install NixOS for a Pi? This is destructive.")]
pi-install-usb host device="/dev/sdc":
    #!/usr/bin/env bash
    set -euo pipefail
    source .just/lib/provision-common.sh

    if [[ "{{host}}" != "core-pi" && "{{host}}" != "hass-pi" ]]; then
        echo "❌ Invalid host: {{host}}. Must be core-pi or hass-pi."; exit 1
    fi
    DEV="{{device}}"; HOST="{{host}}"; MNT="/mnt/{{host}}"
    CRYPT="{{host}}"; CRYPT="${CRYPT%-pi}_crypt"

    pc_sudo_keepalive

    echo "🔄 Syncing with origin so closure hashes match the CI cache..."
    just -f ../justfile jj::pull-all

    pc_require_block_device "$DEV"
    pc_assert_safe_target "$DEV"
    pc_cache_preflight "$HOST" 'linux-rpi.*-modules'

    pc_cleanup "$MNT" "$DEV" "$CRYPT" ""
    pc_wipe "$DEV" 100

    echo "💿 Formatting via disko (will prompt for a NEW LUKS passphrase)..."
    sudo nix run github:nix-community/disko -- \
        --mode destroy,format,mount \
        --argstr device "$DEV" \
        --root-mountpoint "$MNT" ./hosts/{{host}}/disko.nix

    # Guard: <mnt>/boot MUST be on the target disk, not the workstation's ESP.
    pc_assert_esp_on_target "$MNT" "$DEV"

    SYSTEM="$(pc_build_toplevel "$HOST")"
    [ -n "$SYSTEM" ] && [ -e "$SYSTEM" ] || { echo "❌ $HOST closure build failed."; exit 1; }
    pc_install_closure "$MNT" "$SYSTEM"

    echo "💾 Installing Pi 5 firmware config to ESP (direct kernel boot)..."
    pc_assert_esp_on_target "$MNT" "$DEV"   # re-verify right before writing
    ESP="$MNT/boot"
    sudo mkdir -p "${ESP}/nixos"
    KERNEL="$(realpath "${SYSTEM}/kernel")"
    INITRD="$(realpath "${SYSTEM}/initrd")"
    DTBS="$(realpath "${SYSTEM}/dtbs")"
    K_DEST="nixos/$(basename "$KERNEL")"
    I_DEST="nixos/$(basename "$INITRD")"
    D_DEST="nixos/$(basename "$DTBS")-bcm2712-rpi-5-b.dtb"
    sudo cp -fL "$KERNEL" "${ESP}/$K_DEST"
    sudo cp -fL "$INITRD" "${ESP}/$I_DEST"
    sudo cp -fL "$DTBS/broadcom/bcm2712-rpi-5-b.dtb" "${ESP}/$D_DEST"
    # CRITICAL: embed boot.initrd.secrets (clevis JWE, initrd-sshd key) or the
    # first boot fails copy-secrets/sshd and drops to emergency mode.
    pc_append_initrd_secrets "$HOST" "${ESP}/$I_DEST"
    PARAMS="$(cat "${SYSTEM}/kernel-params")"
    echo "init=${SYSTEM}/init $PARAMS" | sudo tee "${ESP}/cmdline.txt" > /dev/null
    printf "[all]\nkernel=%s\ninitramfs %s followkernel\ncmdline=cmdline.txt\narm_64bit=1\nupstream_kernel=1\ndevice_tree=%s\ndtparam=pciex1_gen=3\ndisable_splash=1\nhdmi_force_hotplug=1\nos_check=0\n" \
        "$K_DEST" "$I_DEST" "$D_DEST" | sudo tee "${ESP}/config.txt" > /dev/null
    rm -f /tmp/{{host}}-system

    # Host identity: SSH host keys only (Pi's original behavior; no sops re-encrypt here).
    echo "🔑 Setting up host identity (SSH keys)..."
    persist="$MNT/nix/persist"
    sudo mkdir -p "${persist}/etc/ssh" "${persist}/var/lib/sops/age"
    sudo chmod 700 "${persist}/var/lib/sops/age"
    if [ ! -f "${persist}/etc/ssh/ssh_host_ed25519_key" ]; then
        sudo ssh-keygen -t ed25519 -f "${persist}/etc/ssh/ssh_host_ed25519_key" -N "" -C "$HOST" -q
        sudo ssh-keygen -t rsa -b 4096 -f "${persist}/etc/ssh/ssh_host_rsa_key" -N "" -C "$HOST" -q
        sudo chmod 600 "${persist}/etc/ssh/ssh_host_ed25519_key" "${persist}/etc/ssh/ssh_host_rsa_key"
        sudo chmod 644 "${persist}/etc/ssh/ssh_host_ed25519_key.pub" "${persist}/etc/ssh/ssh_host_rsa_key.pub"
    fi

    pc_clevis_bind_tang "$CRYPT"

    pc_teardown "$MNT" "$CRYPT"
    echo "✅ Installation complete — put the SSD in the Pi and boot."

[group("Provisioning")]
[confirm("🔄 Re-install Pi config to an ALREADY-PROVISIONED SSD in the USB reader (NO wipe)?")]
[doc("Non-destructive in-place update of an installed Pi SSD. Mounts the existing disk via disko, rebuilds the closure, and reinstalls it.")]
pi-update-usb host device="/dev/sdc":
    #!/usr/bin/env bash
    set -euo pipefail
    source .just/lib/provision-common.sh

    # Prompt for sudo upfront and keep it alive in the background
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

    if [[ "{{host}}" != "core-pi" && "{{host}}" != "hass-pi" ]]; then
        echo "❌ Invalid host: {{host}}. Must be core-pi or hass-pi."
        exit 1
    fi

    echo "🔄 Syncing with origin to ensure closure hashes match the CI cache..."
    just -f ../justfile jj::pull-all

    if [ ! -b "{{device}}" ]; then
        echo "❌ Error: Target {{device}} is not a valid block device! Please check lsblk."
        exit 1
    fi
    echo "📊 Target Device Info ({{device}}):"
    lsblk "{{device}}" || true
    echo "----------------------------------------"

    CRYPT_NAME="{{host}}"
    CRYPT_NAME="${CRYPT_NAME%-pi}_crypt"
    MNT="/mnt/{{host}}"

    echo "🔍 Pre-flight check: verifying cache coverage for {{host}}..."
    output=$(nix build --no-link --dry-run .#nixosConfigurations.{{host}}.config.system.build.toplevel 2>&1) || true
    
    # Extract only the derivations that will be built, ignoring fast-builds or aliases
    build_list=$(echo "$output" | sed -n '/will be built:/,/will be fetched\|^$/p' | grep -E '^\s+/nix/store' | awk '{print $1}' || true)
    heavy_builds=$(echo "$build_list" | grep -vE -- '-(nixos-system-|boot\.json|linux-rpi.*-modules)\.drv$' || true)

    if [ -n "$heavy_builds" ]; then
        echo "❌ Cache miss detected! Heavy compilations required:"
        echo "$heavy_builds" | sed 's/^/  /'
        echo ""
        echo "💡 To fix this and ensure a 0-build deployment:"
        echo "   1. Commit any local changes to your git tree (dirty trees change hashes!)."
        echo "   2. Push to GitHub so CI can build and push to Attic."
        echo "   3. Run 'just jj::pull-all' to sync to the exact cached commit."
        echo "   4. Retry this deployment script."
        exit 1
    fi
    echo "✓ Closure fully covered by Attic! Proceeding with deployment."

    echo "🧹 Cleaning up existing mounts and LUKS mappings before mounting..."
    for mp in $(awk '$2 ~ "^'"$MNT"'" {print $2}' /proc/mounts | sort -r); do
        sudo fuser -km "$mp" 2>/dev/null || true
        sudo umount "$mp" 2>/dev/null || sudo umount -l "$mp" 2>/dev/null || true
    done
    disk_name=$(basename {{device}})
    for part in /sys/class/block/${disk_name}*/holders/*; do
        [ -e "$part" ] && sudo cryptsetup close "$(basename "$(readlink "$part")")" 2>/dev/null || true
    done
    sudo cryptsetup close "$CRYPT_NAME" 2>/dev/null || true

    # Forcefully unmount any auto-mounted partitions from the host OS
    for mp in $(lsblk -rn -o MOUNTPOINT {{device}} | awk 'NF'); do
        sudo umount "$mp" 2>/dev/null || sudo umount -l "$mp" 2>/dev/null || true
    done
    sudo udevadm settle 2>/dev/null || true

    echo "🔓 Mounting existing SSD via disko (enter the Pi LUKS passphrase when prompted)..."
    sudo nix run github:nix-community/disko -- \
        --mode mount \
        --argstr device {{device}} \
        --root-mountpoint "$MNT" \
        ./hosts/{{host}}/disko.nix

    # Terminate any stale background builds for this host to prevent Nix store lock deadlocks
    if pgrep -f "nix build .#nixosConfigurations.{{host}}" >/dev/null; then
        echo "🧹 Terminating stale background builds for {{host}} to free store locks..."
        pkill -f "nix build .#nixosConfigurations.{{host}}" || true
        sleep 1
    fi

    echo "🏗️ Building {{host}} closure (using local emulation for small derivations)..."
    nix build .#nixosConfigurations.{{host}}.config.system.build.toplevel \
        --option sandbox false \
        --option builders "" \
        --out-link /tmp/{{host}}-system

    SYSTEM="$(readlink /tmp/{{host}}-system)"

    echo "💿 Installing closure (skipping bootloader — done host-side below)..."
    sudo nixos-install --root "$MNT" --system "${SYSTEM}" --no-root-passwd --no-bootloader

    echo "💾 Installing Pi 5 firmware config to ESP (direct kernel boot)..."
    ESP="$MNT/boot"
    sudo mkdir -p "${ESP}/nixos"
    
    KERNEL="$(realpath "${SYSTEM}/kernel")"
    INITRD="$(realpath "${SYSTEM}/initrd")"
    DTBS="$(realpath "${SYSTEM}/dtbs")"
    
    K_DEST="nixos/$(basename "$KERNEL")"
    I_DEST="nixos/$(basename "$INITRD")"
    D_DEST="nixos/$(basename "$DTBS")-bcm2712-rpi-5-b.dtb"
    
    sudo cp -fL "$KERNEL" "${ESP}/$K_DEST"
    sudo cp -fL "$INITRD" "${ESP}/$I_DEST"
    sudo cp -fL "$DTBS/broadcom/bcm2712-rpi-5-b.dtb" "${ESP}/$D_DEST"
    # CRITICAL: embed boot.initrd.secrets or the boot drops to emergency mode.
    pc_append_initrd_secrets "{{host}}" "${ESP}/$I_DEST"

    PARAMS="$(cat "${SYSTEM}/kernel-params")"
    echo "init=${SYSTEM}/init $PARAMS" | sudo tee "${ESP}/cmdline.txt" > /dev/null
    
    printf "[all]\nkernel=%s\ninitramfs %s followkernel\ncmdline=cmdline.txt\narm_64bit=1\nupstream_kernel=1\ndevice_tree=%s\ndtparam=pciex1_gen=3\ndisable_splash=1\nhdmi_force_hotplug=1\nos_check=0\n" \
        "$K_DEST" "$I_DEST" "$D_DEST" | sudo tee "${ESP}/config.txt" > /dev/null

    rm -f /tmp/{{host}}-system

    echo "🔌 Unmounting..."
    sudo umount -l "$MNT/boot" 2>/dev/null || true
    sudo umount -l "$MNT/nix/persist" 2>/dev/null || true
    sudo umount -l "$MNT/nix" 2>/dev/null || true
    sudo cryptsetup close "$CRYPT_NAME" || true
    echo "✅ In-place update complete — put the SSD in the Pi and boot."


# --- Router LXC ---


[group("Router")]
router-secrets file="site.yml":
    @echo "🔐 Editing OpenWrt secrets: {{file}}..."
    @cd ../openwrt-secrets && sops {{file}}

[group("Router")]
router-provision:
    @echo "⚙️  Provisioning OpenWrt routers via Ansible..."
    @cd ../openwrt-config && just provision


[group("Provisioning")]
[doc("Re-bind the LUKS volume on an installed core-pi SSD to the Tang cluster.")]
core-rebind-tang device="/dev/sdf":
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Prompt for sudo upfront and keep it alive in the background
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    
    echo "🔓 Mounting existing SSD via disko (enter the Pi LUKS passphrase when prompted)..."
    sudo nix run github:nix-community/disko -- \
        --mode mount \
        --argstr device {{device}} \
        --root-mountpoint /mnt/core-pi \
        ./hosts/core-pi/disko.nix
        
    LUKS_DEV=$(sudo cryptsetup status core_crypt | awk '/device:/ {print $2}')
    if [ -n "$LUKS_DEV" ]; then
        echo "⚠️ Unbinding old Tang key..."
        sudo clevis luks unbind -d "$LUKS_DEV" -s 1 || echo "No old key in slot 1 or failed to unbind."
        echo "🔗 Binding LUKS partition to Tang CLUSTER for silent boot..."
        echo "Will prompt for LUKS password to authorize Tang cluster binding..."
        sudo clevis luks bind -d "$LUKS_DEV" sss '{"t": 1, "pins": {"tang": [{"url": "http://10.0.0.5:7654", "adv": "hosts/nixos-nvme/tang-adv.jws"}, {"url": "http://10.0.0.21:7654", "adv": "hosts/hass-pi/tang-adv.jws"}, {"url": "http://10.0.0.15:7654", "adv": "hosts/orin-nano/tang-adv.jws"}]}}'
    else
        echo "⚠️ Could not find mapped device core_crypt for Tang binding."
    fi
    
    echo "🔌 Unmounting..."
    sudo umount -l /mnt/core-pi/boot 2>/dev/null || true
    sudo umount -l /mnt/core-pi/nix/persist 2>/dev/null || true
    sudo umount -l /mnt/core-pi/nix 2>/dev/null || true
    sudo cryptsetup close core_crypt || true
    echo "✅ Tang Cluster Re-binding complete."
