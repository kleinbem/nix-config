# shellcheck shell=bash
# Shared helpers for USB-reader NixOS provisioning (pi-install-usb / orin-install-usb).
#
# Sourced from the destructive install recipes in ../deployment.just. The caller
# is responsible for `set -euo pipefail`. CWD is the nix-config repo root (recipes
# reference ./hosts/... and ../nix-secrets), so relative paths resolve from there.
#
# Everything here uses sudo; call pc_sudo_keepalive first. Functions take explicit
# arguments (no reliance on just {{...}} substitution) so they are unit-checkable.
#
# Host-SPECIFIC steps that intentionally stay in the recipes:
#   - bootloader install (Pi = config.txt/direct-kernel; Orin = systemd-boot)
#   - disko invocation (per-host disko.nix) and any host-specific retry logic

# ── sudo ──────────────────────────────────────────────────────────────────────
pc_sudo_keepalive() {
  sudo -v
  # Refresh the sudo timestamp until the parent recipe exits.
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" 2>/dev/null || exit
  done 2>/dev/null &
}

# ── safety guards (workstation shares disko partlabels with the target SSDs) ───
# Refuse to touch a non-USB disk, or one backing THIS host's / or /boot.
pc_assert_safe_target() {
  local dev="$1" d rootpk bootpk tran
  [ -b "$dev" ] || {
    echo "❌ SAFETY ABORT: $dev is not a block device."
    exit 1
  }
  tran=$(lsblk -dno TRAN "$dev" 2>/dev/null)
  if [ "$tran" != "usb" ]; then
    echo "❌ SAFETY ABORT: $dev is not USB-attached (TRAN=$tran). Refusing to wipe."
    exit 1
  fi
  d=$(basename "$dev")
  rootpk=$(lsblk -no PKNAME "$(findmnt -no SOURCE / 2>/dev/null)" 2>/dev/null | head -1)
  bootpk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /boot 2>/dev/null)" 2>/dev/null | head -1)
  if [ "$d" = "$rootpk" ] || [ "$d" = "$bootpk" ]; then
    echo "❌ SAFETY ABORT: $dev backs THIS host's / ($rootpk) or /boot ($bootpk)."
    exit 1
  fi
  echo "✅ Safety: $dev is a USB disk, not this host's root/boot."
}

# The disko partlabels (disk-main-ESP/luks) also exist on the workstation's own
# root disk, so <mnt>/boot could resolve to the wrong ESP after a wipe window.
# Assert it is on the target disk before ANY write. Call after disko mounts.
pc_assert_esp_on_target() {
  local mnt="$1" dev="$2" src pk
  src=$(findmnt -no SOURCE "$mnt/boot" 2>/dev/null)
  pk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)
  if [ "$pk" != "$(basename "$dev")" ]; then
    echo "❌ SAFETY ABORT: $mnt/boot ($src) is on disk '$pk', not $(basename "$dev") — partlabel collision with the workstation ESP. NOT writing."
    sudo umount -R "$mnt" 2>/dev/null || true
    exit 1
  fi
  echo "✅ Safety: $mnt/boot is on $(basename "$dev")."
}

pc_require_block_device() {
  local dev="$1"
  [ -b "$dev" ] || {
    echo "❌ Error: $dev is not a valid block device (check lsblk)."
    exit 1
  }
  echo "📊 Target device ($dev):"
  lsblk -o NAME,SIZE,TRAN,MODEL,MOUNTPOINTS "$dev" || true
  echo "----------------------------------------"
}

# ── cache pre-flight ──────────────────────────────────────────────────────────
# Abort if the host toplevel needs heavy local compilation (a cache miss), so we
# never silently burn hours emulating aarch64. Set PC_ALLOW_BUILD=1 to bypass
# (e.g. an Orin closure not yet warmed in CI that you accept building locally).
# $1 = host attr; $2 = extra `-`-anchored egrep alternation of drv names expected/OK
#      to build locally ("" for none, e.g. "linux-rpi.*-modules" or "l4t-.*");
# $3.. = extra nix args (e.g. the OVERRIDES flags) so the dry-run evaluates the
#      SAME closure the recipe will actually build.
pc_cache_preflight() {
  local host="$1" extra="${2:-}"
  shift $(($# >= 2 ? 2 : $#))
  local output build_list heavy exclude
  if [ "${PC_ALLOW_BUILD:-0}" = "1" ]; then
    echo "⏭️  PC_ALLOW_BUILD=1 — skipping cache pre-flight for $host (local build permitted)."
    return 0
  fi
  echo "🔍 Pre-flight: verifying Attic cache coverage for $host..."
  output=$(nix build --no-link --dry-run ".#nixosConfigurations.$host.config.system.build.toplevel" "$@" 2>&1) || true
  build_list=$(echo "$output" | sed -n '/will be built:/,/will be fetched\|^$/p' | grep -E '^\s+/nix/store' | awk '{print $1}' || true)
  exclude="-(nixos-system-|boot\.json${extra:+|$extra})\.drv\$"
  heavy=$(echo "$build_list" | grep -vE -- "$exclude" || true)
  if [ -n "$heavy" ]; then
    echo "❌ Cache miss — these would compile locally:"
    # shellcheck disable=SC2001 # per-line prefix; no clean parameter-expansion form
    echo "$heavy" | sed 's/^/  /'
    echo "💡 For a 0-build install: commit → push → CI builds+caches to Attic → 'just jj::pull-all' → retry."
    echo "   (Or set PC_ALLOW_BUILD=1 to build locally on purpose.)"
    exit 1
  fi
  echo "✓ Closure fully covered by cache."
}

# ── teardown ──────────────────────────────────────────────────────────────────
# Robustly release a target before wiping. Handles the failure mode where a flaky
# USB enclosure re-enumerates its device letter mid-run (e.g. sdc->sdd), leaving
# the SAME mountpoint stacked in /proc/mounts over a now-vanished ("ghost") device.
# $1=mnt  $2=dev  $3=crypt-name  $4=vg-name (optional; "" if LUKS-direct, no LVM)
pc_cleanup() {
  local mnt="$1" dev="$2" crypt="$3" vg="${4:-}" u=0 dn p dm h
  echo "🧹 Cleaning up mounts / device-mapper for $dev ($mnt)..."

  # 1. Unmount everything under $mnt, looping until clean (peels stacked/ghost
  #    mounts one layer per pass). umount by mountpoint works even when the
  #    backing device is gone. Hard cap so a genuinely-stuck mount can't spin.
  while awk -v m="$mnt" '$2 ~ "^"m"(/|$)"' /proc/mounts | grep -q . && [ "$u" -lt 30 ]; do
    for p in $(awk -v m="$mnt" '$2 ~ "^"m"(/|$)" {print $2}' /proc/mounts | sort -r | uniq); do
      sudo fuser -km "$p" 2>/dev/null || true
      sudo umount "$p" 2>/dev/null || sudo umount -l "$p" 2>/dev/null || true
    done
    u=$((u + 1))
    sudo udevadm settle 2>/dev/null || true
  done

  # 2. Unmount any host-auto-mounted partitions of the device itself.
  for p in $(lsblk -rn -o MOUNTPOINT "$dev" 2>/dev/null | awk 'NF'); do
    sudo umount "$p" 2>/dev/null || sudo umount -l "$p" 2>/dev/null || true
  done
  sudo sync

  # 3. LVM teardown (Orin: vg over LUKS). No-op for LUKS-direct hosts.
  if [ -n "$vg" ]; then
    sudo vgchange -an "$vg" 2>/dev/null || true
    for dm in $(sudo dmsetup ls 2>/dev/null | awk '{print $1}' | grep -E "^${vg}"); do
      sudo dmsetup remove -f --retry "$dm" 2>/dev/null || true
    done
    sudo vgremove -f "$vg" 2>/dev/null || true
    sudo rm -f "/etc/lvm/backup/${vg}" "/etc/lvm/archive/${vg}"_*.vg 2>/dev/null || true
    sudo rm -rf "/dev/${vg}" 2>/dev/null || true
  fi

  # 4. Close any LUKS mapping backed by this disk, then the named container.
  dn=$(basename "$dev")
  for h in /sys/class/block/"${dn}"*/holders/*; do
    [ -e "$h" ] && sudo cryptsetup close "$(basename "$(readlink "$h")")" 2>/dev/null || true
  done
  sudo cryptsetup close "$crypt" 2>/dev/null || true
  sudo dmsetup remove -f --retry "$crypt" 2>/dev/null || true
  sudo udevadm settle 2>/dev/null || true

  # 5. Report if anything is still mounted (caller may choose to bail).
  if awk -v m="$mnt" '$2 ~ "^"m"(/|$)"' /proc/mounts | grep -q .; then
    echo "⚠️  $mnt still has mounts after ${u} cleanup passes:" >&2
    awk -v m="$mnt" '$2 ~ "^"m"(/|$)"' /proc/mounts >&2
  fi
}

# Wipe GPT + all partition signatures. $1=dev  $2=leading-dd MiB (default 100).
pc_wipe() {
  local dev="$1" ddmib="${2:-100}" p
  echo "💿 Wiping $dev (dd ${ddmib}MiB + zap GPT + wipefs)..."
  # wipefs partitions FIRST, while the nodes still exist (glob, not ls|grep).
  for p in "${dev}"*; do
    [ "$p" = "$dev" ] && continue
    [ -b "$p" ] || continue
    sudo wipefs -a "$p" 2>/dev/null || true
  done
  sudo dd if=/dev/zero of="$dev" bs=1M count="$ddmib" status=none || true
  sudo sgdisk --zap-all "$dev" 2>/dev/null || true
  sudo wipefs -a "$dev" 2>/dev/null || true
  sudo blockdev --rereadpt "$dev" 2>/dev/null || sudo partprobe "$dev" 2>/dev/null || true
  sudo udevadm settle 2>/dev/null || true
}

# ── build / install ───────────────────────────────────────────────────────────
# Build a host toplevel and print its store path. $1=host  $2..=extra nix args.
pc_build_toplevel() {
  local host="$1"
  shift
  # Kill stale background builds of this host to avoid store-lock deadlocks.
  if pgrep -f "nix build .#nixosConfigurations.${host}" >/dev/null; then
    pkill -f "nix build .#nixosConfigurations.${host}" || true
    sleep 1
  fi
  local link="/tmp/${host}-system"
  nix build ".#nixosConfigurations.${host}.config.system.build.toplevel" \
    --option sandbox false --option builders "" \
    "$@" --out-link "$link" >&2
  readlink "$link"
}

# nixos-install without the bootloader (bootctl fails under QEMU on aarch64; the
# recipes install the loader host-side afterwards). $1=mnt  $2=system-store-path
pc_install_closure() {
  local mnt="$1" system="$2"
  echo "💿 Installing closure to $mnt (bootloader done host-side)..."
  sudo nixos-install --root "$mnt" --system "$system" --no-root-passwd --no-bootloader
}

# Embed boot.initrd.secrets (clevis JWE, initrd-sshd host key, …) into an initrd
# already copied to the ESP. CRITICAL: without this, initrd-nixos-copy-secrets
# (and initrd sshd) fail on the FIRST boot and the host drops to EMERGENCY MODE.
# We skip nixos-install's bootloader step (bootctl can't run under QEMU), but the
# appender is a self-contained host-side script (its own coreutils/cpio PATH), so
# it runs fine on the x86 workstation. No-op for hosts that declare no secrets.
# $1=host attr  $2=path to the initrd on the ESP  $3..=extra nix args (OVERRIDES)
pc_append_initrd_secrets() {
  local host="$1" initrd="$2"
  shift 2
  local base appender
  base=$(nix build --no-link --print-out-paths \
    ".#nixosConfigurations.${host}.config.system.build.initialRamdiskSecretAppender" \
    "$@" 2>/dev/null || true)
  appender="${base}/bin/append-initrd-secrets"
  if [ -n "$base" ] && [ -x "$appender" ]; then
    echo "🔐 Appending initrd secrets to ${initrd}..."
    sudo "$appender" "$initrd"
  else
    echo "ℹ️  No initrd-secrets appender for ${host} (no boot.initrd.secrets) — skipping."
  fi
}

# ── host identity ─────────────────────────────────────────────────────────────
# Generate persistent SSH host keys + machine-id under <mnt>/nix/persist and derive
# the sops age key from the ed25519 host key. Prints the age public key on stdout.
# $1=mnt  $2=host-label
pc_host_identity() {
  local mnt="$1" host="$2" persist age_pub
  persist="$mnt/nix/persist"
  echo "🔑 Setting up host identity for $host..." >&2
  sudo mkdir -p "${persist}/etc/ssh" "${persist}/var/lib/sops/age"
  sudo chmod 700 "${persist}/var/lib/sops/age"

  if [ ! -f "${persist}/etc/ssh/ssh_host_ed25519_key" ]; then
    sudo ssh-keygen -t ed25519 -f "${persist}/etc/ssh/ssh_host_ed25519_key" -N "" -C "$host" -q
    sudo ssh-keygen -t rsa -b 4096 -f "${persist}/etc/ssh/ssh_host_rsa_key" -N "" -C "$host" -q
    sudo chmod 600 "${persist}/etc/ssh/ssh_host_ed25519_key" "${persist}/etc/ssh/ssh_host_rsa_key"
    sudo chmod 644 "${persist}/etc/ssh/ssh_host_ed25519_key.pub" "${persist}/etc/ssh/ssh_host_rsa_key.pub"
  fi

  age_pub=$(sudo cat "${persist}/etc/ssh/ssh_host_ed25519_key.pub" | ssh-to-age)
  sudo cat "${persist}/etc/ssh/ssh_host_ed25519_key" | ssh-to-age --private-key |
    sudo tee "${persist}/var/lib/sops/age/host.txt" >/dev/null
  sudo chmod 600 "${persist}/var/lib/sops/age/host.txt"

  if [ ! -f "${persist}/etc/machine-id" ]; then
    systemd-id128 new | sudo tee "${persist}/etc/machine-id" >/dev/null
    sudo chmod 444 "${persist}/etc/machine-id"
  fi
  echo "$age_pub"
}

# Add a host age key to nix-secrets/.sops.yaml (after the last age key) and
# re-encrypt. $1=age-public-key  $2=comment-label
pc_sops_add_and_reencrypt() {
  local age_pub="$1" label="$2" sops_yaml="../nix-secrets/.sops.yaml"
  if grep -qF "$age_pub" "$sops_yaml"; then
    echo "   Age key already in .sops.yaml — skipping re-encryption."
    return 0
  fi
  awk -v key="$age_pub" -v label="$label" '
        /^[[:space:]]*- "age1/ { last = NR }
        { lines[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                print lines[i]
                if (i == last) { print "          # Host Key (" label ")"; print "          - \"" key "\"" }
            }
        }' "$sops_yaml" >/tmp/sops_updated.yaml && mv /tmp/sops_updated.yaml "$sops_yaml"
  echo "🔐 Re-encrypting secrets (YubiKey touch may be required)..."
  (cd ./nix-secrets && sops updatekeys --yes secrets.yaml)
  echo "✅ Secrets updated — remember to commit nix-secrets + nix-config."
}

# ── clevis / Tang ─────────────────────────────────────────────────────────────
# Bind a LUKS container to the Tang cluster (t=1: any one server unlocks). Uses
# the repo's tang-adv.jws advertisements — keep those in sync with the live Tang
# servers or the resulting binding won't decrypt. $1=crypt-name
pc_clevis_bind_tang() {
  local crypt="$1" luks_dev
  echo "🔗 Binding $crypt to the Tang cluster for silent boot..."
  luks_dev=$(sudo cryptsetup status "$crypt" | awk '/device:/ {print $2}')
  if [ -z "$luks_dev" ]; then
    echo "⚠️  Could not find mapped device $crypt for Tang binding."
    return 0
  fi
  echo "   (will prompt for the LUKS passphrase to authorize the binding)"
  sudo clevis luks bind -d "$luks_dev" sss \
    '{"t": 1, "pins": {"tang": [
            {"url": "http://10.0.0.5:7654",  "adv": "hosts/nixos-nvme/tang-adv.jws"},
            {"url": "http://10.0.0.21:7654", "adv": "hosts/hass-pi/tang-adv.jws"},
            {"url": "http://10.0.0.15:7654", "adv": "hosts/orin-nano/tang-adv.jws"}
        ]}}' ||
    echo "⚠️  Tang binding failed — you may need to enter the passphrase on boot."
}
