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

        # Neutral warmth for Night Light (5500K) instead of aggressive default 4700K yellow
        "org/gnome/settings-daemon/plugins/color" = {
          night-light-temperature = lib.hm.gvariant.mkUint32 5500;
        };
      };
    };
}
