{
  sops = {
    # defaultSopsFile/defaultSopsFormat/validateSopsFiles now default
    # fleet-wide in modules/nixos/base.nix.

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
      # Wires into nix.conf via modules/nixos/core.nix's `!include` (gated on
      # this secret existing) so the nix daemon can authenticate GitHub
      # fetches of the private kleinbem-secrets repo. Every other host that
      # ever needs a *genuinely fresh* kleinbem-secrets commit (not already
      # sitting in its local store from some other build/copy) needs this —
      # nasbook was simply never given it, unlike nixos-nvme/orin-nano.
      # Confirmed missing live 2026-09-20: nixos-upgrade.service failed with
      # "unable to download... kleinbem-secrets/archive/<rev>.tar.gz: HTTP
      # error 404" (kleinbem-secrets is private; unauthenticated archive
      # fetches always 404 regardless of which commit). mac-mini, core-pi,
      # and hass-pi are missing it too — same latent gap, not yet fixed
      # there.
      github_read_all_token = {
        mode = "0440";
        group = "wheel";
      };
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
