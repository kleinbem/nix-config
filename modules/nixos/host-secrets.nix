# Plaintext key material that must exist unencrypted on the host — the
# initrd SSH host key, LUKS key files copied into the initrd — lives in a
# root-only directory on the host and is generated there (`just
# access::host-keygen <host>`). It is referenced by string path, never as a
# Nix path, so it never enters the store, a closure or Attic. An encrypted
# copy can be kept in kleinbem-secrets as a backup; Nix never reads it.
{ config, lib, ... }:

let
  cfg = config.my.hostSecrets;
in
{
  options.my.hostSecrets = {
    dir = lib.mkOption {
      type = lib.types.str;
      default = "/nix/persist/secrets";
      readOnly = true;
      description = "Root-only directory for host-local plaintext keys (persistent on every host).";
    };
    initrdSshKey = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dir}/initrd/ssh_host_ed25519_key";
      readOnly = true;
      description = "This host's initrd SSH host key (generated on the host).";
    };
  };

  config.systemd.tmpfiles.rules = [
    "d ${cfg.dir} 0700 root root -"
    "d ${cfg.dir}/initrd 0700 root root -"
  ];
}
