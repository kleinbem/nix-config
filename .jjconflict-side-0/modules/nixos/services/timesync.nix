{
  config,
  lib,
  ...
}:

let
  cfg = config.my.services.timesync;
in
{
  options.my.services.timesync = {
    # Intentional break from the Switchboard `default = false` rule: time sync
    # is foundational (NixOS itself defaults timesyncd to true), and the
    # timesyncd→chrony swap should apply everywhere this module is imported.
    # Hosts that need to opt out (LXC guests inheriting host time, recovery
    # images, etc.) can still set `my.services.timesync.enable = false`.
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Chrony-based time sync (replaces systemd-timesyncd).";
    };
  };

  config = lib.mkIf cfg.enable {
    # timesyncd waits for a netlink route-change event before its first NTP
    # query. On hosts where the network comes up before timesyncd starts
    # listening, that event never arrives and the clock drifts uncorrected —
    # which then breaks anything that signs short-lived JWTs (e.g. GitHub
    # Actions runner session creation).
    services.timesyncd.enable = false;

    services.chrony = {
      enable = true;
      # Allow chrony to step the clock if drift exceeds 1s, in any of the
      # first 3 update cycles. Critical for hosts whose RTC may be wildly
      # off at boot (containers, VMs, devices without a battery-backed RTC).
      extraConfig = ''
        makestep 1.0 3
      '';
    };
  };
}
