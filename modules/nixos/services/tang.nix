{
  config,
  lib,
  ...
}:

let
  cfg = config.my.services.tang;
in
{
  options.my.services.tang = {
    enable = lib.mkEnableOption "Tang server for headless LUKS auto-unlock";
  };

  config = lib.mkIf cfg.enable {
    services.tang = {
      enable = true;
      # Only the physical LAN may ask Tang for a key share. 10.0.0.0/8 used
      # to be allowed, which includes every host's container subnet
      # (10.85.x.0/24): a container reads the host's /nix/store, every
      # host's cryptroot JWE sits there (kleinbem-secrets is a flake
      # input), so any container could have unwrapped any host's LUKS key
      # by talking to a Tang. Initrd unlock always comes from a 10.0.x.x
      # address (clevis-initrd.nix configures the LAN interface with a /16).
      ipAddressAllow = [
        "10.0.0.0/16"
        "127.0.0.1/32"
      ];
    };

    networking.firewall.allowedTCPPorts = [ 7654 ];

    # Losing these breaks every clevis binding to this Tang (hosts fall back
    # to their LUKS passphrase). Secure tier = age-encrypted to the
    # YubiKeys, so an off-site copy doesn't hand the keys to anyone else.
    my.backup.items.tang = {
      tier = "secure";
      paths = [ "/var/lib/private/tang" ];
    };
  };
}
