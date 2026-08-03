# Fix + auto-recovery for a long-standing flaky interaction between OpenSSH's
# FIDO2/security-key signing path and this desktop's YubiKey (USB 1050:0406).
#
# ACTUAL root cause, found 2026-08-03 via `ssh -vvv` on a genuinely fresh
# (non-multiplexed, non-agent) connection: this key's ED25519-SK credential
# requires a PIN ("verify-required"), not just touch. OpenSSH's ssh-sk-helper
# always tries touch-only first, which always fails for this credential
# (logged misleadingly as `sk_sign failed`/`incorrect passphrase supplied to
# decrypt private key`), then automatically retries via $SSH_ASKPASS to
# actually prompt for the PIN. That retry goes through a GUI dialog
# (lxqt-openssh-askpass) which is unreliable — when it fails to show or
# capture input, ssh reports the generic `sign_and_send_pubkey ... invalid
# format` / "agent refused operation" errors that were previously (2026-07-30)
# misdiagnosed as a USB/CTAP2 hardware glitch requiring `usbreset`. The real,
# repeatable fix is forcing PIN entry through the terminal instead of the
# flaky GUI dialog: `SSH_ASKPASS_REQUIRE=never` — confirmed reliable across
# multiple fresh-connection tests once found.
#
# The usbreset-based retry below is kept as a defensive fallback only (in
# case a genuine USB hiccup ever does occur), not the primary fix anymore.
{ pkgs, ... }:
let
  wrappedSsh = pkgs.writeShellScriptBin "ssh" ''
    set -uo pipefail
    real_ssh="${pkgs.openssh}/bin/ssh"
    usbreset="${pkgs.usbutils}/bin/usbreset"
    yubikey_id="1050:0406"

    # The actual fix: force PIN entry through the terminal instead of the
    # unreliable GUI askpass dialog (see file header for how this was found).
    export SSH_ASKPASS_REQUIRE=never

    errfile="$(mktemp)"
    trap 'rm -f "$errfile"' EXIT

    "$real_ssh" "$@" 2> >(tee "$errfile" >&2)
    status=$?

    # Defensive fallback only — the SSH_ASKPASS_REQUIRE fix above should
    # prevent this from firing in the first place.
    if [ "$status" -eq 255 ] \
      && grep -qE 'sign_and_send_pubkey.*(invalid format|agent refused operation)' "$errfile"; then
      echo "ssh: detected FIDO2 signing glitch — resetting YubiKey ($yubikey_id) and retrying once..." >&2
      "$usbreset" "$yubikey_id" >/dev/null 2>&1 || true
      sleep 1
      exec "$real_ssh" "$@"
    fi

    exit "$status"
  '';
in
{
  home.packages = [ wrappedSsh ];

  # home.packages alone isn't enough: any devshell (direnv/nix develop, e.g.
  # this repo's own workspace shell) prepends ITS packages ahead of the
  # home-manager profile in $PATH, and several devshells transitively pull in
  # a raw openssh (via git, jj, etc.) — silently shadowing this wrapper for
  # as long as a devshell is active, which in practice is most of the time.
  # Confirmed 2026-08-03: this wrapper was written 2026-07-30 and had never
  # actually been invoked since, for exactly this reason. shellAliases wins
  # over $PATH lookup for interactive shells regardless of devshell layering
  # (though NOT for other programs spawning `ssh` as a subprocess directly).
  home.shellAliases.ssh = "${wrappedSsh}/bin/ssh";
}
