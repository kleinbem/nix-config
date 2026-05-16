{ inputs, ... }:

{
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";

    # Use a persistent host key for decryption
    age.keyFile = "/nix/persist/var/lib/sops/age/host.txt";

    # We only need the user password for now
    secrets = {
      martin_password = {
        neededForUsers = true;
      };
      u2f_keys = { };
    };
  };
}
