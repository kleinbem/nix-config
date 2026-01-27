{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.my.services.code-server;
  user = "martin";
in
{
  options.my.services.code-server = {
    enable = lib.mkEnableOption "VS Code Server";
  };

  config = lib.mkIf cfg.enable {
    systemd.services.code-server = {
      description = "VS Code Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = user;
        Group = "users";
        ExecStart = "${pkgs.code-server}/bin/code-server --bind-addr 0.0.0.0:4444 --auth none";
        Restart = "always";
        Environment = "HOME=/home/${user}";
      };
    };

    networking.firewall.allowedTCPPorts = [ 4444 ];
  };
}
