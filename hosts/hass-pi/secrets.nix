# hass-pi — SOPS secrets.
#
# Enables fully hands-off NetBird enrollment: the netbird-autojoin oneshot
# (modules/nixos/networking.nix) runs `netbird up --setup-key` automatically on
# the next autoUpgrade pull — NO SSH and NO YubiKey on the Pi. hass-pi decrypts
# with its own SSH host key (Tang already unlocks LUKS at boot; this keeps the
# box autonomous).
#
# hass-pi's age recipient is already in nix-secrets/.sops.yaml
# (age13prane4e59gww9rs2qu06ahd6krvd76fpd68jpya5xt7632chgks8k0yd8, derived from
# /etc/ssh/ssh_host_ed25519_key). DEPLOY ORDER MATTERS — secrets.yaml must be
# re-encrypted for that recipient BEFORE this lands on hass-pi:
#
#   1. cd nix-secrets && sops updatekeys secrets.yaml   (workstation YubiKey)
#      → commit + push nix-secrets.
#   2. Update nix-config's lock to that nix-secrets commit
#      (nix flake update nix-secrets, or the sync_locks autopilot).
#   3. Commit + push nix-config. hass-pi auto-enrolls on its next pull
#      (or `just deployment::deploy-fleet` for immediate).
#
# A premature deploy only fails the switch (stays on current generation) — not
# fatal — but do step 1 first to avoid a failed autoUpgrade cycle.
# NOTE: confirm netbird_setup_key in secrets.yaml is a *reusable* key (it's
# shared with nixos-nvme/orin-nano); a one-time key already consumed won't join.
{ inputs, ... }:

{
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Don't fail the *build* validating secret presence against the sops file.
    # CI builds this host's toplevel with dummy `{}` secrets (--override-input
    # nix-secrets /tmp/dummy-secrets), so sops-install-secrets' build-time
    # manifest check ("key 'attic_pull_token' cannot be found") would abort the
    # whole toplevel — the documented sops-nix CI workaround. Real decryption at
    # activation is unaffected (it uses the real secrets.yaml on the host).
    validateSopsFiles = false;

    secrets = {
      # Consumed by modules/nixos/networking.nix → netbird-autojoin oneshot,
      # which runs `netbird up --setup-key` when the daemon reports NeedsLogin.
      netbird_setup_key = { };
      # Read-only Attic pull token. Activates modules/nixos/attic-pull.nix
      # (netrc Bearer auth + NetBird routing) so hass-pi can substitute from the
      # private cache instead of compiling (e.g. the linux-rpi kernel).
      attic_pull_token = { };
    };
  };
}
