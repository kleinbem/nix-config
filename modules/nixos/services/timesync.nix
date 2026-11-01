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
    # Breaks the Switchboard `default = false` rule on purpose: time sync is
    # foundational (NixOS defaults timesyncd on too). Opt out where needed.
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
    # timesyncd waits for a netlink route event before its first query; if the
    # network was up before it started, that never comes and the clock drifts,
    # breaking short-lived JWTs (GitHub Actions runner sessions).
    services.timesyncd.enable = false;

    services.chrony = {
      enable = true;
      # Step on any drift over 1s, not just the first 3 updates: on hosts
      # without a working RTC, failed early syncs use up that budget and
      # chrony then slews a years-long offset.
      # No `rtcsync`: NixOS enables rtcautotrim, which conflicts with it.
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
