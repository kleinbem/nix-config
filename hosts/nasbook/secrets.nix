{ inputs, ... }:

{
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";

    # Use host SSH keys for automated decryption
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      paperless_password = { };
      restic_password = { };
      restic_system_password = { };
      rclone_config = { };
    };
  };
}
