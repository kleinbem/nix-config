{
  config,
  pkgs,
  ...
}:

let
  monitorsXml = ./files/monitors.xml;
in
{
  # Synchronize GDM display layout to eliminate boot/login mode-switch flicker
  systemd.tmpfiles.rules = [
    "d /var/lib/gdm/.config 0700 gdm gdm -"
    "L+ /var/lib/gdm/.config/monitors.xml - gdm gdm - ${monitorsXml}"
  ];

  # Enable DDC/CI monitor communication (I2C) so hardware color gain,
  # color temperature, and brightness can be controlled from Linux CLI via ddcutil
  hardware.i2c.enable = true;
  environment.systemPackages = [ pkgs.ddcutil ];

  # Set both external monitors to 100% brightness on graphical session startup
  systemd.user.services.set-monitor-brightness = {
    description = "Set external monitors to 100% brightness via DDC/CI";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "set-max-brightness" ''
        for d in 1 2; do
          ${pkgs.ddcutil}/bin/ddcutil --display "$d" setvcp 10 100 2>/dev/null || true
        done
      ''}";
    };
  };

  # User session display, font scaling, and color configuration
  home-manager.users.${config.my.username} =
    { lib, ... }:
    {
      xdg.configFile."monitors.xml" = {
        source = monitorsXml;
        force = true;
      };

      dconf.settings = {
        # Optimized font scaling for 1440p displays at 100% integer scale
        # (crisp 1:1 pixel rendering without fractional framebuffer downsampling overhead)
        "org/gnome/desktop/interface" = {
          text-scaling-factor = 1.25;
        };

        # Night Light disabled by default; tuned to neutral 5500K if ever turned on
        "org/gnome/settings-daemon/plugins/color" = {
          night-light-enabled = false;
          night-light-schedule-automatic = false;
          night-light-temperature = lib.hm.gvariant.mkUint32 5500;
        };
      };
    };
}
