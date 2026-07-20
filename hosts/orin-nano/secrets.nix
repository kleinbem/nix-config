{ inputs, ... }:

{
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";

    # Use a persistent host key for decryption
    age.keyFile = "/nix/persist/var/lib/sops/age/host.txt";

    # We only need the user password for now
    secrets = {
      martin_password_hash = {
        neededForUsers = true;
      };
      u2f_keys = { };
      github_read_all_token = {
        mode = "0440";
        group = "wheel";
      };
      netbird_setup_key = { };
      # Read-only Attic pull token — activates modules/nixos/attic-pull.nix so
      # nightly upgrades substitute the CI-built closure instead of compiling
      # jetpack/l4t packages on-device.
      attic_pull_token = { };
      attic_push_token = { };
      github_pat = {
        owner = "martin";
      };
      brave_api_key = {
        owner = "martin";
      };
      github_app_id = {
        owner = "martin";
      };
      github_app_installation_id = {
        owner = "martin";
      };

      github_app_private_key = {
        owner = "martin";
      };
    };
  };
}
