# shellcheck shell=bash
# Shared helpers for the *-install-usb recipes in ../deployment.just. The caller
# sets `set -euo pipefail`, runs from the nix-config root and calls
# pc_sudo_keepalive first. Bootloader install and disko stay in the recipes.

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
  local dev="$1" d rootpk bootpk tran rootsrc bootsrc
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
  # A tmpfs root has a non-block SOURCE, where `lsblk PKNAME` exits 32 and
  # set -e would abort; only look it up for real block devices.
  rootsrc=$(findmnt -no SOURCE / 2>/dev/null || true)
  bootsrc=$(findmnt -no SOURCE /boot 2>/dev/null || true)
  rootpk=""
  bootpk=""
  [ -b "$rootsrc" ] && rootpk=$(lsblk -no PKNAME "$rootsrc" 2>/dev/null | head -1)
  [ -b "$bootsrc" ] && bootpk=$(lsblk -no PKNAME "$bootsrc" 2>/dev/null | head -1)
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
# Abort on a cache miss so we never burn hours emulating aarch64
# (PC_ALLOW_BUILD=1 bypasses). $1 = host attr; $2 = extra egrep alternation of
# drv names OK to build locally ("" for none); $3.. = nix args (OVERRIDES) so
# the dry-run sees the same closure.
pc_cache_preflight() {
  local host="$1" extra="${2:-}"
  shift $(($# >= 2 ? 2 : $#))
  local output build_list heavy exclude leaves
  if [ "${PC_ALLOW_BUILD:-0}" = "1" ]; then
    echo "⏭️  PC_ALLOW_BUILD=1 — skipping cache pre-flight for $host (local build permitted)."
    return 0
  fi
  echo "🔍 Pre-flight: verifying Attic cache coverage for $host..."
  output=$(nix build --no-link --dry-run ".#nixosConfigurations.$host.config.system.build.toplevel" "$@" 2>&1) || true
  build_list=$(echo "$output" | sed -n '/will be built:/,/will be fetched\|^$/p' | grep -E '^\s+/nix/store' | awk '{print $1}' || true)
  # Config-assembly leaves (etc, activate, units, generated config files) build
  # locally in seconds whenever they miss the cache, e.g. because of real
  # secrets. A real package/kernel miss is named <pkg>-<version>.drv and still stops.
  leaves='nixos-system-|boot\.json|etc|activate|(system|user)-units|unit-.*|.*\.(rules|service|yaml|conf|toml|json)'
  exclude="-(${leaves}${extra:+|$extra})\.drv\$"
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
# Unmount everything at or under $mnt, one stacked layer per pass (capped).
# $mnt itself is usually not a mountpoint (tmpfs roots), so `umount -R $mnt`
# does nothing; matching /proc/mounts by prefix works, even for gone devices.
# $1=mnt
pc_unmount_under() {
  local mnt="$1" u=0 p
  while awk -v m="$mnt" '$2 ~ "^"m"(/|$)"' /proc/mounts | grep -q . && [ "$u" -lt 30 ]; do
    for p in $(awk -v m="$mnt" '$2 ~ "^"m"(/|$)" {print $2}' /proc/mounts | sort -r | uniq); do
      sudo fuser -km "$p" 2>/dev/null || true
      sudo umount "$p" 2>/dev/null || sudo umount -l "$p" 2>/dev/null || true
    done
    u=$((u + 1))
    sudo udevadm settle 2>/dev/null || true
  done
}

# Non-destructive teardown after a SUCCESSFUL install/update: unmount the tree,
# deactivate the VG, and close the LUKS container — WITHOUT vgremove/wipe (the VG
# holds the freshly-installed system). This is what the recipes call at the end;
# do NOT use pc_cleanup there — it destroys the VG. $1=mnt $2=crypt $3=vg (opt)
pc_teardown() {
  local mnt="$1" crypt="$2" vg="${3:-}"
  echo "🔌 Unmounting $mnt and closing $crypt..."
  pc_unmount_under "$mnt"
  sudo sync
  [ -n "$vg" ] && sudo vgchange -an "$vg" 2>/dev/null || true
  sudo cryptsetup close "$crypt" 2>/dev/null || true
  if awk -v m="$mnt" '$2 ~ "^"m"(/|$)"' /proc/mounts | grep -q .; then
    echo "⚠️  $mnt still has mounts after teardown:" >&2
    awk -v m="$mnt" '$2 ~ "^"m"(/|$)"' /proc/mounts >&2
    return 1
  fi
  echo "✅ $mnt fully unmounted; $crypt closed."
}

# Release a target before wiping, including mounts left stacked over a "ghost"
# device after a flaky USB enclosure re-enumerated (sdc -> sdd).
# DESTRUCTIVE: also vgremoves the VG; pre-wipe only.
# $1=mnt  $2=dev  $3=crypt-name  $4=vg-name (optional; "" if LUKS-direct, no LVM)
pc_cleanup() {
  local mnt="$1" dev="$2" crypt="$3" vg="${4:-}" dn p dm h
  echo "🧹 Cleaning up mounts / device-mapper for $dev ($mnt)..."

  # 1. Unmount everything under $mnt (see pc_unmount_under for why prefix-match).
  pc_unmount_under "$mnt"

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
    echo "⚠️  $mnt still has mounts after cleanup:" >&2
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

# Embed boot.initrd.secrets (clevis JWE, initrd-sshd key) into the initrd on the
# ESP. Skipping nixos-install's bootloader step skips this too, and without it
# the first boot drops to emergency mode. The appender runs fine on x86.
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

# Set a host's age key on its `&<anchor>` in kleinbem-secrets/.sops.yaml (one
# place, referenced by many creation_rules), then updatekeys every sops file,
# since any of them may reference the anchor.
# $1=age-public-key  $2=host-label ("mac-mini" -> anchor "mac_mini")
pc_sops_add_and_reencrypt() {
  local age_pub="$1" label="$2" sops_yaml="../kleinbem-secrets/.sops.yaml"
  local anchor="${label//-/_}"
  if grep -qF "$age_pub" "$sops_yaml"; then
    echo "   Age key already in .sops.yaml — skipping re-encryption."
    return 0
  fi
  if ! grep -qE "&${anchor}[[:space:]]" "$sops_yaml"; then
    echo "❌ No '&${anchor}' anchor found in $sops_yaml — this host isn't onboarded" >&2
    echo "   there yet. Add a '&${anchor} age1PLACEHOLDER...' line to the keys: block" >&2
    echo "   and a creation_rules entry referencing it first (see kleinbem-secrets/README.md)." >&2
    return 1
  fi
  # Replace only the value up to the next whitespace, keeping any trailing
  # comment. Not `age1[a-zA-Z0-9]+`: it stops at the "_" in placeholders like
  # age1PLACEHOLDER_NASBOOK and leaves a corrupt recipient.
  sed -i -E "s|(&${anchor}[[:space:]]+)age1[^[:space:]]+|\\1${age_pub}|" "$sops_yaml"
  echo "🔐 Re-encrypting every real content file (YubiKey touch may be required per file)..."
  local f
  while IFS= read -r -d '' f; do
    # Some matches are plain (personas/contact.nix), and updatekeys dies on
    # them; real sops files carry a top-level `sops:` block.
    if ! grep -q '^sops:' "$f"; then
      echo "   skip (not sops-encrypted): ${f#../kleinbem-secrets/}"
      continue
    fi
    echo "   updatekeys: ${f#../kleinbem-secrets/}"
    (cd ../kleinbem-secrets && sops updatekeys --yes "${f#../kleinbem-secrets/}")
  done < <(find ../kleinbem-secrets \
    \( -path '../kleinbem-secrets/.git' -o -path '../kleinbem-secrets/.jj' -o -path '../kleinbem-secrets/keys.d' \) -prune -o \
    -type f \( -name '*.yaml' -o -name '*.nix' \) ! -name '.sops.yaml' -print0)
  echo "✅ Secrets updated — remember to commit kleinbem-secrets + nix-config."
}

# ── FIDO2 (hosts that can't Tang-bind to themselves, e.g. nasbook IS the
#    tang server) ────────────────────────────────────────────────────────────
# Enroll both YubiKeys as FIDO2 LUKS unlock, so losing one doesn't lock the box
# out; the passphrase keyfile authorizes, only the touch needs a human.
# Run against a CLOSED device (pc_teardown first, note the partition path
# before): on an active mapping systemd-cryptenroll fails with "Unlocking via
# keyfile failed: Operation not permitted".
# $1=raw LUKS partition (e.g. /dev/sdc2, not the crypt name)  $2=passphrase-keyfile
pc_fido2_enroll_dual() {
  local luks_dev="$1" pass_file="$2"
  [ -b "$luks_dev" ] || {
    echo "❌ $luks_dev is not a block device."
    return 1
  }
  echo ""
  echo "🔐 Enrolling FIDO2 YubiKeys on ${luks_dev} for boot-time LUKS unlock."
  echo "   Plug in your PRIMARY YubiKey, then press Enter here..."
  read -r _
  sudo systemd-cryptenroll --fido2-device=auto --unlock-key-file="$pass_file" "$luks_dev"
  echo "   ✅ Primary enrolled. Now swap to your BACKUP YubiKey, then press Enter..."
  read -r _
  sudo systemd-cryptenroll --fido2-device=auto --unlock-key-file="$pass_file" "$luks_dev"
  echo "   ✅ Backup enrolled."
}

# ── clevis / Tang ─────────────────────────────────────────────────────────────
# Bind a LUKS container to every OTHER host's Tang server (t=1: any one
# unlocks), each pinned by thumbprint from inventory.nix (scripts/tang-config.sh).
# $1=crypt-name $2=host $3=optional keyfile with the EXISTING passphrase
# (non-interactive); omit for the normal interactive prompt.
pc_clevis_bind_tang() {
  local crypt="$1" host="$2" keyfile="${3:-}" luks_dev cfg
  echo "🔗 Binding $crypt to the Tang servers for silent boot..."
  luks_dev=$(sudo cryptsetup status "$crypt" | awk '/device:/ {print $2}')
  if [ -z "$luks_dev" ]; then
    echo "⚠️  Could not find mapped device $crypt for Tang binding."
    return 0
  fi
  cfg=$(bash scripts/tang-config.sh "$host")
  local bind_opts=(-d "$luks_dev")
  if [ -n "$keyfile" ]; then
    bind_opts+=(-y -f -k "$keyfile")
  else
    bind_opts+=(-y)
    echo "   (will prompt for the LUKS passphrase to authorize the binding)"
  fi
  sudo clevis luks bind "${bind_opts[@]}" sss "$cfg" ||
    echo "⚠️  Tang binding failed — you may need to enter the passphrase on boot."
}
