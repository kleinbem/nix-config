{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.my.services.glances;
in
{
  options.my.services.glances = {
    enable = lib.mkEnableOption "Glances System Monitor";
  };

  config = lib.mkIf cfg.enable {
    systemd.services.glances = {
      description = "Glances System Monitor";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.glances}/bin/glances -w -p 61208";
        Restart = "always";
        User = "nobody"; # Secure default
      };
    };

    networking.firewall.allowedTCPPorts = [ 61208 ];

    environment.systemPackages = [ pkgs.glances ];
  };
}
