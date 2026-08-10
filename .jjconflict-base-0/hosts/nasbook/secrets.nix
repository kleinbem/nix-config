{ inputs, ... }:

{
  sops = {
    # NOTE: nasbook is not yet a real recipient on nix/shared.yaml — its key
    # is still a placeholder in kleinbem-secrets/.sops.yaml (host
    # offline/unreachable as of 2026-08-06). Pre-existing condition, not
    # something this cutover changes; nasbook can't decrypt real secrets
    # from either repo until it's provisioned and added as a recipient.
    defaultSopsFile = "${inputs.nix-secrets}/nix/shared.yaml";
    defaultSopsFormat = "yaml";

    # Don't fail the *build* validating secret presence against the sops file
    # — matches every other host. Was missing here (pre-existing, unrelated
    # to the 2026-08-07 cutover): discovered because kleinbem-secrets' stricter
    # split-file layout made a real `nix build .#nixosConfigurations.nasbook
    # .config.system.build.sops-nix-manifest` against CI's dummy tree actually
    # fail ("key 'attic_pull_token' cannot be found") where every other host
    # passed. Not exercised by any current CI workflow (nasbook isn't in
    # build-all.yaml's matrix), so harmless in practice, but there's no reason
    # to leave it inconsistent with the rest of the fleet.
    validateSopsFiles = false;

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
