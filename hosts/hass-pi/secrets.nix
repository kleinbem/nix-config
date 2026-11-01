# hass-pi — SOPS secrets, decrypted with the host's own SSH key so the box
# stays autonomous (no SSH or YubiKey needed to enroll in NetBird).
#
# If the host key ever changes: `sops updatekeys nix/shared.yaml` in
# kleinbem-secrets first, bump nix-config's lock, then deploy. Otherwise the
# switch fails. netbird_setup_key must be a reusable key (shared with other hosts).
_: {
  sops = {
    age.sshKeyPaths = [ "/nix/persist/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      # Consumed by modules/nixos/networking.nix → netbird-autojoin oneshot,
      # which runs `netbird up --setup-key` when the daemon reports NeedsLogin.
      netbird_setup_key = { };
      # Read-only Attic pull token. Activates modules/nixos/attic-pull.nix
      # (netrc Bearer auth + NetBird routing) so hass-pi can substitute from the
      # private cache instead of compiling (e.g. the linux-rpi kernel).
      attic_pull_token = { };
      # Included into nix.conf (modules/nixos/core.nix) so the daemon can fetch
      # the private kleinbem-secrets repo; unauthenticated fetches 404.
      github_read_all_token = {
        mode = "0440";
        group = "wheel";
      };
      # Secret ntfy topic — arms the nixos-upgrade-listener (rpi5-node.nix
      # enables it; ConditionPathExists on this secret's path keeps it inert
      # until the key materialises at activation).
      ntfy_deploy_topic = { };
    };
  };
}
