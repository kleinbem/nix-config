# Temporary no-touch SSH access grants, using authorized_keys `expiry-time`
# so sshd itself drops the key at the deadline. The key is keys.ssh.fido2-notouch
# (on the YubiKey, enrolled without touch). Deliberately not declarative.
# Re-running replaces the grant, which is how you extend or shorten it. The
# expiry is computed on the target, in the timezone its sshd enforces.

set working-directory := ".."

# Public half of keys.ssh.fido2-notouch, read from modules/nixos/keys.nix.
# Needs authorizedKeysInHomedir (NixOS default) on the target so
# ~/.ssh/authorized_keys is honoured.
_notouch_pubkey := shell("nix eval --raw --impure --expr '(import ./modules/nixos/keys.nix).ssh.fido2-notouch'")

[group("Access")]
[doc("Grant (or replace/extend/shorten) no-touch SSH access to <device> for <duration> (default 24h; try '1h', '30m', '3d'). Re-run any time to change the window.")]
grant-notouch device duration="24h":
    #!/usr/bin/env bash
    set -euo pipefail
    # Terse units -> GNU date words ("24h" -> "24 hours", "3d" -> "3 days")
    spec="$(echo "{{duration}}" | sed -E 's/^([0-9]+)h$/\1 hours/; s/^([0-9]+)d$/\1 days/; s/^([0-9]+)m$/\1 minutes/')"
    expiry="$(ssh {{device}} "date -d '+${spec}' +%Y%m%d%H%M%S")"
    # grep -v exits 1 when no line is left; >1 is a read error and must not empty the file.
    remote_script="set -euo pipefail; mkdir -p ~/.ssh; chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; grep -v 'GitHubNoTouchV2' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp || [ \$? -eq 1 ]; mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys; echo 'no-touch-required,expiry-time=\"${expiry}\" {{_notouch_pubkey}}' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys"
    ssh {{device}} "$remote_script"
    echo "✅ {{device}}: no-touch access granted until ${expiry} (device-local time, {{duration}} from now)."

[group("Access")]
[doc("Revoke no-touch SSH access from <device> immediately, without waiting for expiry.")]
revoke-notouch device:
    ssh {{device}} "set -e; grep -v 'GitHubNoTouchV2' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp || [ \$? -eq 1 ]; mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys"
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

# Stage-2 keyfile per host: "<path> <sops key>".
[private]
_data-key host:
    #!/usr/bin/env bash
    case "{{host}}" in
      nasbook) echo /nix/persist/secrets/nasbook-data.key nasbook_data_luks_key ;;
      orin-nano) echo /nix/persist/etc/crypt/frigate.key orin_frigate_luks_key ;;
      *) echo "no data-disk keyfile known for {{host}}" >&2; exit 1 ;;
    esac

# Data disks opened in stage 2 from a host-local keyfile have no other key
# slot. Keep an encrypted copy in kleinbem-secrets (nix/per-host/<host>.yaml,
# base64); data-key-restore puts it back after a reinstall. Nix never reads
# it. The plaintext only travels through the SSH pipe into sops.
[group("Access")]
[doc("Back up <host>'s data-disk keyfile into kleinbem-secrets, sops-encrypted (sudo on <host>, YubiKey for sops). Hosts: nasbook, orin-nano.")]
data-key-backup host:
    #!/usr/bin/env bash
    set -euo pipefail
    read -r key name < <(just access::_data-key {{host}})
    secrets="${KLEINBEM_SECRETS:-../kleinbem-secrets}"
    f=nix/per-host/{{host}}.yaml
    # sudo asks on the host's TTY. Everything but the key line goes to the
    # terminal (the prompt ends in a newline, so it shows at once); only the
    # KEY: line is captured. Piping the password into `sudo -S` was rejected.
    remote="sudo -p \"sudo password on {{host}}:"$'\n'"\" sh -c \"printf KEY:; base64 -w0 $key; echo\""
    b64=$(ssh -t {{host}} "$remote" \
      | awk '{ sub(/\r$/, "") } /^KEY:/ { print substr($0, 5); next } { print > "/dev/stderr"; fflush("/dev/stderr") }') \
      || { echo "reading the key on {{host}} failed; nothing written" >&2; exit 1; }
    bytes=$(printf '%s' "$b64" | base64 -d 2>/dev/null | wc -c) || bytes=0
    [ "$bytes" -ge 32 ] || { echo "key from {{host}} is empty, short or not base64 ($bytes bytes); nothing written" >&2; exit 1; }
    cd "$secrets"
    if [ -f "$f" ]; then
      printf '%s' "$b64" | jq -Rs . | sops set --value-stdin "$f" "[\"$name\"]"
    else
      # The first secret creates the file, with the recipients from .sops.yaml.
      printf '%s: %s\n' "$name" "$b64" \
        | sops encrypt --input-type yaml --output-type yaml --filename-override "$f" /dev/stdin > "$f.new"
      mv "$f.new" "$f"
    fi
    unset b64
    echo "✓ $name ($bytes bytes) stored in $f; commit kleinbem-secrets"

# Never overwrites: an existing keyfile may be the one the disk opens with.
[group("Access")]
[doc("Restore <host>'s data-disk keyfile from kleinbem-secrets (YubiKey for sops, sudo on <host>). Refuses to overwrite.")]
data-key-restore host:
    #!/usr/bin/env bash
    set -euo pipefail
    read -r key name < <(just access::_data-key {{host}})
    secrets="${KLEINBEM_SECRETS:-../kleinbem-secrets}"
    tmp=$(mktemp -p "${XDG_RUNTIME_DIR:-/tmp}")
    rtmp=""
    trap 'rm -f "$tmp"; [ -z "$rtmp" ] || ssh {{host}} rm -f "$rtmp"' EXIT
    (cd "$secrets" && sops -d --extract "[\"$name\"]" nix/per-host/{{host}}.yaml) | base64 -d > "$tmp"
    bytes=$(wc -c < "$tmp")
    [ "$bytes" -ge 32 ] || { echo "$name decodes to $bytes bytes; nothing written" >&2; exit 1; }
    rtmp=$(ssh {{host}} mktemp)
    scp -q "$tmp" {{host}}:"$rtmp"
    d=$(dirname "$key")
    ssh -t {{host}} "sudo -p 'sudo password on {{host}}: ' sh -c '[ ! -e $key ] || { echo \"$key exists; not overwriting\" >&2; exit 1; }; [ -d $d ] || install -d -m 0700 $d; install -m 0400 -o root -g root $rtmp $key'"
    echo "✓ $name ($bytes bytes) installed at {{host}}:$key"

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
