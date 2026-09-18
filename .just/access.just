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
    remote_script="set -euo pipefail; mkdir -p ~/.ssh; chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; grep -v 'GitHubNoTouchV2' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp || true; mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys; echo 'expiry-time=\"${expiry}\" {{_notouch_pubkey}}' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys"
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
