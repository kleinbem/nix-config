{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.my.services.silverbullet;
  user = "martin";
  sbDir = "/home/${user}/Develop/Notes"; # Default notes directory
in
{
  options.my.services.silverbullet = {
    enable = lib.mkEnableOption "SilverBullet Notes";
  };

  config = lib.mkIf cfg.enable {
    # Ensure notes directory exists for the user
    systemd.tmpfiles.rules = [
      "d ${sbDir} 0750 ${user} users - -"
    ];

    systemd.services.silverbullet = {
      description = "SilverBullet Notes Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = user;
        Group = "users";
        # Port 3333
        ExecStart = "${pkgs.silverbullet}/bin/silverbullet --port 3333 ${sbDir}";
        Restart = "always";
      };
    };

    networking.firewall.allowedTCPPorts = [ 3333 ];
  };
}
