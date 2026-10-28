{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.timesync;
  saveScript = pkgs.writeShellScript "fake-hwclock-save" ''
    DIR=$(${pkgs.coreutils}/bin/dirname "${cfg.persistentClock.path}")
    ${pkgs.coreutils}/bin/mkdir -p "$DIR"
    ${pkgs.coreutils}/bin/date +%s > "${cfg.persistentClock.path}.tmp"
    ${pkgs.coreutils}/bin/mv -f "${cfg.persistentClock.path}.tmp" "${cfg.persistentClock.path}"
  '';
  restoreScript = pkgs.writeShellScript "fake-hwclock-restore" ''
    STAMP="${cfg.persistentClock.path}"
    if [ ! -s "$STAMP" ]; then
      echo "fake-hwclock: No timestamp file at $STAMP. Skipping."
      exit 0
    fi
    SAVED_TIME=$(${pkgs.coreutils}/bin/cat "$STAMP" 2>/dev/null || echo 0)
    CURRENT_TIME=$(${pkgs.coreutils}/bin/date +%s)
    if [ "$SAVED_TIME" -gt "$CURRENT_TIME" ]; then
      echo "fake-hwclock: System clock is in the past ($(${pkgs.coreutils}/bin/date -d "@$CURRENT_TIME" '+%Y-%m-%d %H:%M:%S')). Restoring to $(${pkgs.coreutils}/bin/date -d "@$SAVED_TIME" '+%Y-%m-%d %H:%M:%S')."
      ${pkgs.coreutils}/bin/date -s "@$SAVED_TIME"
      ${pkgs.util-linux}/bin/hwclock --systohc 2>/dev/null || true
    else
      echo "fake-hwclock: System clock ($(${pkgs.coreutils}/bin/date -d "@$CURRENT_TIME" '+%Y-%m-%d %H:%M:%S')) is ahead of saved timestamp. No adjustment needed."
    fi
  '';
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

    persistentClock = {
      enable = lib.mkOption {
        type = lib.types.bool;
        # On everywhere: it only ever moves the clock forward, so hosts with
        # a good RTC lose nothing, and any host whose RTC is missing, dead or
        # simply wrong boots near the real time instead of years behind.
        default = true;
        description = "Save and restore the system clock across reboots, for hosts whose RTC is missing, dead, battery-less or wrong.";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default =
          if config.environment.persistence ? "/nix/persist" then
            "/nix/persist/var/lib/fake-hwclock/timestamp"
          else
            "/var/lib/fake-hwclock/timestamp";
        description = "Path where the timestamp is stored across reboots.";
      };
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
      #
      # Note: NixOS automatically enables rtcfile and rtcautotrim (see
      # services.chrony.enableRTCTrimming), which conflicts with `rtcsync`.
      # chrony trims the RTC through /dev/rtc; persistentClock below covers
      # hosts where that is missing or dead.
      extraConfig = ''
        makestep 1.0 -1
      '';
    };

    systemd.services = lib.mkIf cfg.persistentClock.enable {
      fake-hwclock-restore = {
        description = "Restore system clock from persistent storage";
        wantedBy = [ "sysinit.target" ];
        before = [
          "sysinit.target"
          "shutdown.target"
        ];
        after = [ "local-fs.target" ];
        unitConfig = {
          DefaultDependencies = false;
          ConditionPathExists = cfg.persistentClock.path;
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = restoreScript;
        };
      };

      fake-hwclock-save = {
        description = "Save system clock to persistent storage on shutdown";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
          ExecStop = saveScript;
        };
      };

      fake-hwclock-tick = {
        description = "Periodically save system clock to persistent storage";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = saveScript;
        };
      };
    };

    systemd.timers = lib.mkIf cfg.persistentClock.enable {
      fake-hwclock-tick = {
        description = "Periodically save system clock to persistent storage";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "3min";
          OnUnitActiveSec = "10min";
        };
      };
    };
  };
}
