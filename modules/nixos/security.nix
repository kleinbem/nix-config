{
  pkgs,
  ...
}:

let
  user = "martin";
  home = "/home/${user}";
  clamDir = "/var/lib/clamav";

  # Notification script that bridges systemd (root/clamav) -> user session (dbus)
  notifyScript = pkgs.writeShellScript "clamav-notify" ''
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
    export DISPLAY=":0"

    VIRUS="$CLAM_VIRUSEVENT_VIRUSNAME"
    FILE="$CLAM_VIRUSEVENT_FILENAME"

    # Send desktop notification
    ${pkgs.libnotify}/bin/notify-send \
      -u critical \
      -a "ClamAV" \
      -i "security-high" \
      "🚨 VIRUS DETECTED" \
      "<b>Virus:</b> $VIRUS\n<b>File:</b> $FILE"

    # Log to system journal
    echo "VIRUS DETECTED: $VIRUS in $FILE"
  '';
in
{
  environment.systemPackages = with pkgs; [
    clamav
    clamtk # GUI
    libnotify # For notifications
  ];

  # ==========================================
  # HARDENING & AUDITING
  # ==========================================
  security = {
    apparmor = {
      enable = true;
      killUnconfinedConfinables = true;
    };
    audit = {
      enable = false;
      # rules = [ "-a exit,always -F arch=b64 -S execve" ]; # Log all command executions
    };
    auditd.enable = false;
    protectKernelImage = true;
  };

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
    services.clamav-smart-scan = {
      description = "ClamAV Smart Scan (Recently Modified Files)";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        echo "🛡️ Starting ClamAV Smart Scan..."
        ${pkgs.findutils}/bin/find ${home} \
          -mtime -1 -type f \
          -not -path "*/.cache/*" -not -path "*/.git/*" -not -path "*/node_modules/*" \
          -print0 \
        | ${pkgs.findutils}/bin/xargs -0 -r ${pkgs.clamav}/bin/clamdscan --multiscan --fdpass
      '';
    };

    timers.clamav-smart-scan = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
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

  # ---------------------------
  # Resource Optimization
  # ---------------------------
  # Run scans in background priority to avoid slowing down the system
  systemd.services.clamav-daemon.serviceConfig = {
    Nice = 19;
    IOSchedulingClass = "idle";
  };
  systemd.services.clamav-clamonacc.serviceConfig = {
    Nice = 19;
    IOSchedulingClass = "idle";
  };
}
