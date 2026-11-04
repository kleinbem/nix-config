# Key material that must be plaintext on the host (initrd SSH host key, initrd
# LUKS keyfiles) lives in a root-only dir there, made by
# `just access::host-keygen <host>`. Referenced by string path only, so it
# never enters the store or Attic.
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
