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
    };
  };
}
