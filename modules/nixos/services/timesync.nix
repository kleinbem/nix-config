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
      # Allow chrony to step the clock on any large drift, not just the
      # first 3 updates. Confirmed live on nasbook (no working RTC —
      # "RTC driver could not be initialised", boots at ~2012): even with
      # DNS/network converging within 15s, the "first 3" budget was
      # already burned by failed sync attempts during the network's own
      # early settling window, so the real first successful sync fell
      # outside it and chrony fell back to slowly *slewing* a ~14-year
      # offset — needing a manual `chronyc makestep` to actually fix.
      # -1 removes the update-count limit entirely: any sync at any time
      # that finds a >1s drift steps instead of slews.
      extraConfig = ''
        makestep 1.0 -1
      '';
    };
  };
}
