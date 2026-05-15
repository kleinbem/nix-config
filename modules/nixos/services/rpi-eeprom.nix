# rpi-eeprom.nix — Automatic Raspberry Pi EEPROM updates
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.my.services.rpi-eeprom;
in
{
  options.my.services.rpi-eeprom = {
    enable = lib.mkEnableOption "Automatic Raspberry Pi EEPROM updates";
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "Systemd calendar expression for the update check.";
    };
    autoApply = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to automatically apply updates (requires reboot to take effect).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.raspberrypi-eeprom ];

    systemd.services.rpi-eeprom-update = {
      description = "Check and apply Raspberry Pi EEPROM updates";
      documentation = [
        "https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#updating-the-bootloader"
      ];

      path = [
        pkgs.raspberrypi-eeprom
        pkgs.binutils
        pkgs.pciutils
      ]; # Ensure tools are in path

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.raspberrypi-eeprom}/bin/rpi-eeprom-update ${lib.optionalString cfg.autoApply "-a"}";
        RemainAfterExit = true;
      };
    };

    systemd.timers.rpi-eeprom-update = {
      description = "Timer for Raspberry Pi EEPROM updates";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
  };
}
