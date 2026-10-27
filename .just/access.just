# Temporary no-touch SSH access grants.
#
# Uses OpenSSH's native authorized_keys `expiry-time` option — sshd rejects
# the key outright past the deadline, no cron/timer/CA needed. One shared
# automation identity (keys.ssh.fido2-notouch — hardware-backed, resident on
# the YubiKey, just enrolled without a touch requirement) grantable to any
# host for any duration. Bypasses the normal declarative
# build→push→deploy round-trip on purpose: this is meant to be as fast and
# disposable as the access itself.
#
# Re-running for the same device REPLACES the existing grant with a fresh
# one computed from now — that's how you "extend" (run again with a longer
# duration) or shorten it (run again with a shorter one). The expiry is
# computed on the TARGET host itself, in its own local timezone, so it
# always matches what that host's sshd will actually enforce.

set working-directory := ".."

# Public half of keys.ssh.fido2-notouch (kleinbem/modules/nixos/keys.nix) —
# read from there at call time so this can never drift from the source of
# truth. Requires the target's authorizedKeysInHomedir to be true (NixOS
# default) so ~/.ssh/authorized_keys is actually honored alongside the
# Nix-managed /etc/ssh/authorized_keys.d/<user>.
_notouch_pubkey := shell("nix eval --raw --impure --expr '(import ./modules/nixos/keys.nix).ssh.fido2-notouch'")

[group("Access")]
[doc("Grant (or replace/extend/shorten) no-touch SSH access to <device> for <duration> (default 24h; try '1h', '30m', '3d'). Re-run any time to change the window.")]
grant-notouch device duration="24h":
    #!/usr/bin/env bash
    set -euo pipefail
    # Terse units -> GNU date words ("24h" -> "24 hours", "3d" -> "3 days")
    spec="$(echo "{{duration}}" | sed -E 's/^([0-9]+)h$/\1 hours/; s/^([0-9]+)d$/\1 days/; s/^([0-9]+)m$/\1 minutes/')"
    expiry="$(ssh {{device}} "date -d '+${spec}' +%Y%m%d%H%M%S")"
    remote_script="set -euo pipefail; mkdir -p ~/.ssh; chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; grep -v 'GitHubNoTouchV2' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp || true; mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys; echo 'no-touch-required,expiry-time=\"${expiry}\" {{_notouch_pubkey}}' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys"
    ssh {{device}} "$remote_script"
    echo "✅ {{device}}: no-touch access granted until ${expiry} (device-local time, {{duration}} from now)."

[group("Access")]
[doc("Revoke no-touch SSH access from <device> immediately, without waiting for expiry.")]
revoke-notouch device:
    ssh {{device}} "grep -v 'GitHubNoTouchV2' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp || true; mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys"
    echo "✅ {{device}}: no-touch access revoked."

[group("Access")]
[doc("Show whether <device> currently has a no-touch grant, and when it expires.")]
notouch-status device:
    @ssh {{device}} "grep 'GitHubNoTouchV2' ~/.ssh/authorized_keys 2>/dev/null" \
        && echo "^ grant present on {{device}} (see expiry-time above)" \
        || echo "no grant present on {{device}}"

# Host-local plaintext keys (modules/nixos/host-secrets.nix) are generated on
# the host itself and never leave it. The script travels base64-encoded so
# sudo can read its password from the TTY while the script comes on stdin.
_on_host host script:
    #!/usr/bin/env bash
    set -euo pipefail
    b64=$(printf '%s' {{ quote(script) }} | base64 -w0)
    if [ "{{host}}" = "$(hostname)" ]; then
        printf '%s' "$b64" | base64 -d | sudo bash
    else
        ssh -t {{host}} "printf '%s' '$b64' | base64 -d | sudo bash"
    fi

[group("Access")]
[doc("Generate <host>'s initrd SSH host key in /nix/persist/secrets (root-only, never in the store). Keeps an existing key; prints the public key.")]
host-keygen host:
    @just access::_on_host {{host}} '\
      set -eu; d=/nix/persist/secrets/initrd; \
      install -d -m 0700 /nix/persist/secrets "$d"; \
      [ -f "$d/ssh_host_ed25519_key" ] || ssh-keygen -q -t ed25519 -N "" -C "initrd@{{host}}" -f "$d/ssh_host_ed25519_key"; \
      chmod 0600 "$d/ssh_host_ed25519_key"; \
      cat "$d/ssh_host_ed25519_key.pub"'

# Step 1 of moving nasbook's data-disk key out of kleinbem-secrets: create a
# new random key on nasbook and add it to the LUKS header next to the old one
# (the old one is still in nasbook's store from the repo copy). Deploy, reboot,
# confirm /mnt/data unlocks, then run nasbook-data-drop-old-key.
[group("Access")]
[doc("nasbook: add a new host-local data-disk LUKS key (old key stays until nasbook-data-drop-old-key).")]
nasbook-data-rekey:
    @just access::_on_host nasbook '\
      set -eu; new=/nix/persist/secrets/nasbook-data.key; \
      dev=$(cryptsetup status nasbook_data_crypt | sed -n "s/^ *device: *//p"); \
      old=$(ls -1 /nix/store/*-source/initrd/data_luks_key_nasbook 2>/dev/null | head -n 1); \
      [ -n "$dev" ] && [ -n "$old" ] || { echo "data disk not open or old key not found" >&2; exit 1; }; \
      install -d -m 0700 /nix/persist/secrets; \
      if [ ! -f "$new" ]; then (umask 077; head -c 64 /dev/urandom > "$new"); fi; \
      cryptsetup luksAddKey --key-file "$old" "$dev" "$new" 2>/dev/null || cryptsetup open --test-passphrase --key-file "$new" "$dev"; \
      cryptsetup open --test-passphrase --key-file "$new" "$dev" && echo "new key works on $dev"'

[group("Access")]
[doc("nasbook: remove the old (leaked) data-disk key from the LUKS header. Run only after a reboot unlocked /mnt/data with the new key.")]
nasbook-data-drop-old-key:
    @just access::_on_host nasbook '\
      set -eu; new=/nix/persist/secrets/nasbook-data.key; \
      dev=$(cryptsetup status nasbook_data_crypt | sed -n "s/^ *device: *//p"); \
      old=$(ls -1 /nix/store/*-source/initrd/data_luks_key_nasbook 2>/dev/null | head -n 1); \
      cryptsetup open --test-passphrase --key-file "$new" "$dev" || { echo "new key does not open $dev; refusing" >&2; exit 1; }; \
      cryptsetup luksRemoveKey --key-file "$old" "$dev"; \
      cryptsetup luksDump "$dev" | grep -E "^ *[0-9]+: luks2" '

# nasbook's data disk has a single key slot: the host-local keyfile. Keep an
# encrypted copy in kleinbem-secrets (nix/per-host/nasbook.yaml,
# nasbook_data_luks_key, base64) so a reinstall can restore it with
#   sops -d --extract '["nasbook_data_luks_key"]' nix/per-host/nasbook.yaml | base64 -d
# Nix never reads it. The plaintext only travels through the SSH pipe into sops.
[group("Access")]
[doc("Back up nasbook's data-disk key into kleinbem-secrets, sops-encrypted (sudo on nasbook, YubiKey for sops).")]
nasbook-data-backup:
    #!/usr/bin/env bash
    set -euo pipefail
    secrets="${KLEINBEM_SECRETS:-../kleinbem-secrets}"
    f=nix/per-host/nasbook.yaml
    # sudo asks on nasbook's TTY. Everything but the key line goes to the
    # terminal (the prompt ends in a newline, so it shows at once); only the
    # KEY: line is captured. Piping the password into `sudo -S` was rejected.
    remote=$'sudo -p "sudo password on nasbook:\n" sh -c "printf KEY:; base64 -w0 /nix/persist/secrets/nasbook-data.key; echo"'
    b64=$(ssh -t nasbook "$remote" \
      | awk '{ sub(/\r$/, "") } /^KEY:/ { print substr($0, 5); next } { print > "/dev/stderr"; fflush("/dev/stderr") }') \
      || { echo "reading the key on nasbook failed; nothing written" >&2; exit 1; }
    [ "${#b64}" -eq 88 ] || { echo "unexpected key length (${#b64}); nothing written" >&2; exit 1; }
    cd "$secrets"
    if [ -f "$f" ]; then
      printf '%s' "$b64" | jq -Rs . | sops set --value-stdin "$f" '["nasbook_data_luks_key"]'
    else
      # The first secret creates the file, with the recipients from .sops.yaml.
      printf 'nasbook_data_luks_key: %s\n' "$b64" \
        | sops encrypt --input-type yaml --output-type yaml --filename-override "$f" /dev/stdin > "$f.new"
      mv "$f.new" "$f"
    fi
    unset b64
    echo "✓ nasbook_data_luks_key stored in nix/per-host/nasbook.yaml; commit kleinbem-secrets"

# Read-only unlock check for <host> (needs its sudo password once). Unlock
# policy, every host: Tang (any other host) → primary/backup YubiKey (FIDO2) →
# passphrase → initrd SSH on :2222 to type the passphrase.
[group("Access")]
[doc("Read-only: which unlock methods <host>'s root disk has, whether its Tang JWE opens it, and whether its Tang key matches inventory.nix.")]
unlock-audit host:
    #!/usr/bin/env bash
    set -euo pipefail
    crypt=$(nix eval --raw .#nixosConfigurations.{{host}}.config.my.boot.clevis-initrd.luksDevice)
    thp=$(nix eval --raw --impure --expr '(import ./inventory.nix).tang."{{host}}".thp')
    jwe=$(base64 -w0 < "${KLEINBEM_SECRETS:-../kleinbem-secrets}/initrd/cryptroot_{{host}}.jwe")
    script=$(cat <<SCRIPT
    set -u
    dev=\$(cryptsetup status $crypt | sed -n 's/^ *device: *//p')
    dump=\$(cryptsetup luksDump "\$dev")
    slots=\$(echo "\$dump" | grep -cE '^ +[0-9]+: luks2')
    fido=\$(echo "\$dump" | grep -c 'systemd-fido2' || true)
    clev=\$(echo "\$dump" | grep -c 'clevis' || true)
    tpm=\$(echo "\$dump" | grep -c 'systemd-tpm2' || true)
    echo "== {{host}} (\$dev)"
    echo "   key slots: \$slots  (FIDO2: \$fido, clevis-in-header: \$clev, TPM2: \$tpm, other incl. passphrase: \$((slots - fido - clev - tpm)))"
    if echo $jwe | base64 -d | nix shell nixpkgs#clevis -c clevis decrypt 2>/dev/null | cryptsetup open --test-passphrase --key-file - "\$dev" 2>/dev/null; then
      echo "   Tang JWE opens the disk: yes"
    else
      echo "   Tang JWE opens the disk: NO"
    fi
    own=\$(nix shell nixpkgs#jose -c sh -c 'for k in /var/lib/tang/*.jwk /var/lib/private/tang/*.jwk; do [ -f "\$k" ] && jose jwk use -i "\$k" -r -u verify -o /dev/null 2>/dev/null && jose jwk thp -i "\$k"; echo; done' 2>/dev/null | grep -m1 .)
    if [ "\$own" = "$thp" ]; then echo "   Tang key matches inventory: yes"; else echo "   Tang key matches inventory: NO (\${own:-none found})"; fi
    SCRIPT
    )
    just access::_on_host {{host}} "$script"
