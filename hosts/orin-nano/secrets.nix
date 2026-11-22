{ secretFile, ... }:

{
  sops = {
    # defaultSopsFile/defaultSopsFormat/validateSopsFiles now default
    # fleet-wide in modules/nixos/base.nix.

    # Use a persistent host key for decryption
    age.keyFile = "/nix/persist/var/lib/sops/age/host.txt";

    # headless.nix wires martin_password (key martin_password_hash);
    # only secrets actually consumed on orin-nano live here.
    secrets = {
      github_read_all_token = {
        mode = "0440";
        group = "wheel";
      };
      netbird_setup_key = { };
      # Read-only Attic pull token — activates modules/nixos/attic-pull.nix so
      # nightly upgrades substitute the CI-built closure instead of compiling
      # jetpack/l4t packages on-device.
      attic_pull_token = { };
      attic_push_token = {
        sopsFile = secretFile "nix/per-host/orin-nano.yaml";
        # attic-login stores the token once for the post-build hook.
        restartUnits = [ "attic-login.service" ];
      };
    };
  };
}
