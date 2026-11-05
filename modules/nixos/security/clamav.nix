{
  config,
  lib,
  pkgs,
  ...
}:

let
  home = "/home/${config.my.username}";
  clamDir = "/var/lib/clamav";

  # clamd runs as `clamav` and has no session bus, so VirusEvent hands the alert
  # to security-notify@ (audit.nix): desktop notification for the user + ntfy.
  # '|' separates the template fields, so it is swapped out of the payload. A
  # unit name caps at 255 chars; the full path is in the journal line. The
  # time+PID suffix keeps a second detection from merging into a running alert.
  notifyScript = pkgs.writeShellScript "clamav-notify" ''
    escape=${lib.getExe' config.systemd.package "systemd-escape"}
    VIRUS="$CLAM_VIRUSEVENT_VIRUSNAME"
    FILE="$CLAM_VIRUSEVENT_FILENAME"
    echo "VIRUS DETECTED: $VIRUS in $FILE"
    name=$(${pkgs.coreutils}/bin/basename -- "$FILE")
    ref="clamav-daemon-journal-$(${pkgs.coreutils}/bin/date +%s)-$$"
    msg="''${VIRUS:0:60} in ''${name:0:60}"
    instance=$($escape "ClamAV-virus-detected|''${msg//|//}|$ref")
    if [ "''${#instance}" -gt 230 ]; then
      instance=$($escape "ClamAV-virus-detected|See-clamav-daemon-journal|$ref")
    fi
    ${lib.getExe' config.systemd.package "systemctl"} start --no-block "security-notify@$instance.service"
  '';

  # Config for clamdscan client
  scanConfig = pkgs.writeText "clamd-scan.conf" ''
    LocalSocket /run/clamav/clamd.ctl
  '';
in
{
  environment.systemPackages = with pkgs; [
    clamav
    clamtk # GUI
    libnotify # For notifications
  ];

  services.clamav = {
    daemon = {
      enable = true;
      settings = {
        DatabaseDirectory = clamDir;
        LogSyslog = true;
        LogTime = true;
        VirusEvent = "${notifyScript}";

        # PUA Detection & Performance
        DetectPUA = true;
        ConcurrentDatabaseReload = true;

        # Performance & On-Access
        OnAccessPrevention = true;
        OnAccessIncludePath = [ "${home}/Downloads" ];
        OnAccessExcludeUname = "clamav";
        OnAccessExtraScanning = true;
      };
    };

    updater = {
      enable = true;
      frequency = 12; # Update every 2 hours
      settings = {
        DatabaseDirectory = clamDir;
        LogSyslog = true;
      };
    };

    clamonacc.enable = true;
  };

  # ---------------------------
  # Smart Scan (Nightly)
  # ---------------------------
  systemd = {
    services = {
      clamav-smart-scan = {
        description = "ClamAV Smart Scan (Recently Modified Files)";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          PrivateTmp = true;
        };
        # Files go in through --file-list, not xargs: thousands of paths on the
        # command line end up in _CMDLINE on every journal line (~130 KB each).
        # --infected keeps the per-file "OK" lines out of the journal.
        script = ''
          echo "🛡️ Starting ClamAV Smart Scan..."
          list=$(mktemp)
          ${pkgs.findutils}/bin/find ${home} \
            -mtime -1 -type f \
            -not -path "*/.cache/*" -not -path "*/.git/*" -not -path "*/node_modules/*" \
            > "$list" || true # files vanishing mid-walk must not abort the scan
          if [ -s "$list" ]; then
            ${pkgs.clamav}/bin/clamdscan -c ${scanConfig} --multiscan --fdpass --infected --file-list="$list" || true
          fi
        '';
      };

      clamav-daemon.serviceConfig = {
        RuntimeDirectoryPreserve = "yes";
        Nice = 19;
        IOSchedulingClass = "idle";
      };

      clamav-clamonacc = {
        after = [ "clamav-daemon.service" ];
        wants = [ "clamav-daemon.service" ];
        serviceConfig = {
          ExecStart = [
            ""
            "${pkgs.clamav}/bin/clamonacc -F --fdpass --wait"
          ];
          Nice = 19;
          IOSchedulingClass = "idle";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    };

    sockets.clamav-daemon.partOf = [ "clamav-daemon.service" ];

    timers.clamav-smart-scan = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    # ---------------------------
    # Permissions Fixes
    # ---------------------------
    # Ensure ClamAV directories exist with correct permissions
    tmpfiles.rules = [
      "d ${clamDir} 0755 clamav clamav - -"
      "d /var/log/clamav 0755 clamav clamav - -"
    ];
  };

  # Lets clamd's VirusEvent start the alert unit, nothing else.
  security.polkit = {
    enable = true;
    extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            subject.user == "clamav" &&
            action.lookup("verb") == "start" &&
            action.lookup("unit").indexOf("security-notify@") == 0) {
          return polkit.Result.YES;
        }
      });
    '';
  };

  boot.kernel.sysctl = {
    # ClamAV On-Access Scanning (essential for large directories)
    "fs.inotify.max_user_watches" = 524288;
  };
}
