{
  sops = {
    # defaultSopsFile/defaultSopsFormat/validateSopsFiles now default
    # fleet-wide in modules/nixos/base.nix.
    #
    # NOTE: nasbook is not yet a real recipient on nix/shared.yaml — its key
    # is still a placeholder in kleinbem-secrets/.sops.yaml (host
    # offline/unreachable as of 2026-08-06). Pre-existing condition, not
    # something this cutover changes; nasbook can't decrypt real secrets
    # from either repo until it's provisioned and added as a recipient.

    # Use host SSH keys for automated decryption
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      # Read-only Attic pull token — activates modules/nixos/attic-pull.nix so
      # nightly upgrades substitute the CI-built closure instead of building.
      attic_pull_token = { };
      paperless_password = { };
      restic_password = { };
      restic_system_password = { };
      rclone_config = { };
      # Consumed by modules/nixos/networking.nix -> netbird-autojoin oneshot,
      # which runs `netbird up --setup-key` when the daemon reports NeedsLogin.
      # Was missing on this host — every other netbird-enabled host already
      # had it — so nasbook's netbird daemon sat at NeedsLogin indefinitely,
      # and cache.kleinbem.dev (netbird-mesh-only, 100.x CGNAT range) was
      # unreachable, breaking container-updater's binary-cache substitution.
      netbird_setup_key = { };
    };
  };
}
