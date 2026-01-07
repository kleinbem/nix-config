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

  # Config for clamdscan client
  scanConfig = pkgs.writeText "clamd-scan.conf" ''
    LocalSocket /run/clamav/clamd.ctl
  '';
in
{
  # Overlay to disable SSH Agent in Gnome Keyring
  # This fixes the conflict with YubiKey/FIDO2 hardware keys
  nixpkgs.overlays = [
    (_: prev: {
      gnome-keyring = prev.gnome-keyring.overrideAttrs (old: {
        configureFlags = old.configureFlags or [ ] ++ [
          "--disable-ssh-agent"
        ];
      });
    })
  ];

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
      killUnconfinedConfinables = false;
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
        | ${pkgs.findutils}/bin/xargs -0 -r ${pkgs.clamav}/bin/clamdscan -c ${scanConfig} --multiscan --fdpass
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

  # ==========================================
  # KERNEL HARDENING & PERFORMANCE
  # ==========================================
  boot = {
    # Privacy & Performance Tweaks
    blacklistedKernelModules = [
      "pcspkr"
      "snd_pcsp"
    ];
    consoleLogLevel = 0;
    kernelParams = [
      "quiet"
      "loglevel=0"
      "udev.log_level=3"
      "acpi_osi=Linux"
      "i915.enable_psr=0"
      "snd_hda_intel.power_save=0"
      "snd_hda_intel.power_save_controller=N"
      "audit=0"
    ];

    # Sysctl Hardening
    kernel.sysctl = {
      # ClamAV On-Access Scanning (essential for large directories)
      "fs.inotify.max_user_watches" = 524288;

      # Security Hardening (Network)
      "net.ipv4.conf.all.log_martians" = true;
      "net.ipv4.conf.all.rp_filter" = "1";
      "net.ipv4.icmp_echo_ignore_broadcasts" = "1";
      "net.ipv4.conf.default.accept_redirects" = "0";
      "net.ipv4.conf.all.accept_redirects" = "0";

      # Security Hardening (Kernel)
      "kernel.dmesg_restrict" = "1";
      "kernel.kptr_restrict" = "2";
    };
  };
}
