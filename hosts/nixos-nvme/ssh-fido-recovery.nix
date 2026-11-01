# ssh wrapper for this desktop's YubiKey (USB 1050:0406). Its ED25519-SK key
# is verify-required, so ssh-sk-helper falls back to $SSH_ASKPASS for the PIN,
# and the GUI askpass is unreliable ("invalid format" / "agent refused
# operation"). SSH_ASKPASS_REQUIRE=never asks in the terminal instead.
# If that still fails: tier 1 resets the USB device, tier 2 restarts a stuck
# ssh-agent (the PIN exchange happens inside the agent).
{ pkgs, ... }:
let
  wrappedSsh = pkgs.writeShellScriptBin "ssh" ''
    set -uo pipefail
    real_ssh="${pkgs.openssh}/bin/ssh"
    usbreset="${pkgs.usbutils}/bin/usbreset"
    yubikey_id="1050:0406"

    # PIN prompt in the terminal, not the unreliable GUI askpass.
    export SSH_ASKPASS_REQUIRE=never

    errfile="$(mktemp)"
    trap 'rm -f "$errfile"' EXIT

    is_glitch() {
      grep -qE 'sign_and_send_pubkey.*(invalid format|agent refused operation)' "$errfile"
    }

    "$real_ssh" "$@" 2> >(tee "$errfile" >&2)
    status=$?

    # Tier 1: a genuine USB hiccup.
    if [ "$status" -eq 255 ] && is_glitch; then
      echo "ssh: detected FIDO2 signing glitch — resetting YubiKey ($yubikey_id) and retrying once..." >&2
      "$usbreset" "$yubikey_id" >/dev/null 2>&1 || true
      sleep 1
      : >"$errfile"
      "$real_ssh" "$@" 2> >(tee "$errfile" >&2)
      status=$?
    fi

    # Tier 2: the agent is stuck, which a USB reset doesn't clear. exec so an
    # interactive session behaves normally afterwards.
    if [ "$status" -eq 255 ] && is_glitch; then
      echo "ssh: still glitching after USB reset — restarting ssh-agent and retrying once more..." >&2
      systemctl --user restart ssh-agent.service 2>/dev/null || true
      sleep 1
      exec "$real_ssh" "$@"
    fi

    exit "$status"
  '';
in
{
  home.packages = [ wrappedSsh ];

  # Devshells put their own openssh ahead of the profile in $PATH, so alias it
  # too. The alias only covers interactive shells, not programs spawning ssh.
  home.shellAliases.ssh = "${wrappedSsh}/bin/ssh";
}
