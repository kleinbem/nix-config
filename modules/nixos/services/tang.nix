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
      # Only the physical LAN may ask Tang, not 10.0.0.0/8: container subnets
      # (10.85.x.0/24) can read the host's /nix/store, where every host's JWE
      # sits, so a container could otherwise unwrap any host's LUKS key.
      # Initrd unlock comes from the LAN /16 (clevis-initrd.nix).
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
