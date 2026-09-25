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
      ipAddressAllow = [
        "10.0.0.0/8"
        "192.168.0.0/16"
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
