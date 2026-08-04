{ inputs, ... }:
{
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";

    # Persistent host key generated during provisioning (provision-common.sh
    # pc_host_identity) — same convention as every other real host.
    age.keyFile = "/nix/persist/var/lib/sops/age/host.txt";

    # Don't fail eval/CI against the dummy secrets.yaml override.
    validateSopsFiles = false;

    # martin_password (sops key: martin_password_hash) is already declared by
    # users/martin/nixos.nix, imported below — but mac-mini overrides
    # hashedPasswordFile in default.nix to use mac_mini_login_pin_hash
    # instead (see that override for why: a host-specific, short PIN rather
    # than martin's real shared password, appropriate here since this box's
    # real security boundary is already the SSH tunnel, not this login).
    secrets = {
      # NetBird — consumed by modules/nixos/networking.nix → netbird-autojoin
      # oneshot. Same shared setup key as orin-nano/core-pi/hass-pi.
      netbird_setup_key = { };

      # Read-only Attic pull token — activates modules/nixos/attic-pull.nix
      # (netrc Bearer auth + NetBird-routed reads). Without this,
      # my.deploy.autoUpgrade.requireCache above is pointless: cache pulls
      # 401 and silently fall back to a local build on this slow CPU,
      # capped/retried forever by RuntimeMaxSec instead of ever succeeding.
      attic_pull_token = { };

      # Host-specific short PIN/password for GDM login over RDP (see
      # default.nix's hashedPasswordFile override) — deliberately NOT
      # martin's real password, chosen directly by martin via sops set,
      # never seen in plaintext by anything else.
      mac_mini_login_pin_hash = {
        neededForUsers = true;
      };
    };
  };
}
