# Auto-recovery for a known-flaky interaction between OpenSSH's built-in
# FIDO2/security-key signing path and this desktop's YubiKey (USB 1050:0406).
#
# Symptom: `sign_and_send_pubkey: signing failed for ED25519-SK "...": invalid
# format` (direct signing) or "... from agent: agent refused operation"
# (agent-mediated), for ANY destination including localhost — confirmed via
# extensive testing on 2026-07-30 to be a USB/CTAP2-level glitch on the
# physical key, not a host, network, or OpenSSH config problem (identical
# openssh binary before/after; fails signing to itself). The only reliable
# fix found was a full USB re-enumeration (unplug/replug). `usbreset` does the
# same thing in software and — confirmed — needs no sudo: the device carries
# systemd-logind's `uaccess` tag, so the logged-in seat user already has
# read/write on the device node.
#
# This wraps `ssh` so that when (and only when) it hits this exact failure
# signature, it resets the key and retries once automatically, instead of
# requiring the manual multi-step recovery dance. Deliberately event-driven,
# not a scheduled/preventive reset — a blind timer could fire mid-touch on an
# unrelated operation and make things worse.
{ pkgs, ... }:
{
  home.packages = [
    (pkgs.writeShellScriptBin "ssh" ''
      set -uo pipefail
      real_ssh="${pkgs.openssh}/bin/ssh"
      usbreset="${pkgs.usbutils}/bin/usbreset"
      yubikey_id="1050:0406"

      errfile="$(mktemp)"
      trap 'rm -f "$errfile"' EXIT

      "$real_ssh" "$@" 2> >(tee "$errfile" >&2)
      status=$?

      if [ "$status" -eq 255 ] \
        && grep -qE 'sign_and_send_pubkey.*(invalid format|agent refused operation)' "$errfile"; then
        echo "ssh: detected FIDO2 signing glitch — resetting YubiKey ($yubikey_id) and retrying once..." >&2
        "$usbreset" "$yubikey_id" >/dev/null 2>&1 || true
        sleep 1
        exec "$real_ssh" "$@"
      fi

      exit "$status"
    '')
  ];
}
