{
  pkgs,
  config,
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
    lxqt.lxqt-openssh-askpass
    lynis # Security auditing
  ];

  # Force the correct SSH_AUTH_SOCK for all sessions.
  # environment.sessionVariables is not enough because PAM/Gnome Keyring
  # overwrites it during X session initialization.
  # extraInit runs after that, allowing us to enforce our agent.
  environment.extraInit = ''
    export SSH_AUTH_SOCK="/run/user/1000/ssh-agent"
  '';

  # ==========================================
  # SSH & YUBIKEY SECURITY
  # ==========================================
  programs.ssh = {
    # Start the standard OpenSSH agent system-wide (replaces HM service)
    startAgent = true;

    # Enable the graphical PIN prompt (essential for Git signing)
    enableAskPassword = true;
    askPassword = "${pkgs.lxqt.lxqt-openssh-askpass}/bin/lxqt-openssh-askpass";
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = true; # Required for MFA
      AuthenticationMethods = "publickey,keyboard-interactive"; # Require BOTH key AND code
    };
  };

  # Disable GNOME's GCR SSH Agent to prevent conflict with programs.ssh
  services = {
    gnome = {
      # Disable GNOME's GCR SSH Agent to prevent conflict with programs.ssh
      gcr-ssh-agent.enable = false;
      gnome-keyring.enable = true;
    };

    clamav = {
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

    # ==========================================
    # FAIL2BAN — Brute-Force Protection
    # ==========================================
    fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "1h";
      bantime-increment = {
        enable = true;
        maxtime = "168h"; # 1 week max for repeat offenders
      };
      jails.sshd = {
        settings = {
          enabled = true;
          port = "ssh";
          filter = "sshd";
          maxretry = 3;
        };
      };
    };

    # ==========================================
    # USBGUARD — USB Device Whitelisting
    # ==========================================
    usbguard = {
      enable = true;
      rules = ''
        # --- Host Controllers & Hubs (always needed) ---
        allow with-interface equals { 09:00:00 }

        # --- Input Devices ---
        # Dell KB216 Wired Keyboard
        allow id 413c:2113
        # Logitech USB Receiver (wireless mouse/keyboard)
        allow id 046d:c548

        # --- Security Keys ---
        # YubiKey 5 (OTP+FIDO+CCID)
        allow id 1050:0407
        # VeriMark DT Fingerprint Key
        allow id 047d:00f2

        # --- Peripherals ---
        # Intel Bluetooth Adapter
        allow id 8087:0026
        # Generic USB2.0 Card Reader
        allow id 0bda:0153
        # ESS Technology USB DAC (Audio)
        allow id 0495:3048
        # USB 2.0 Hub
        allow id 05e3:0610
        # Generic USB 2.0 Hub (Webcam Hub)
        allow id 1a40:0101
        # HD Camera
        allow id 0408:7090
        # Webcam USB Audio
        allow id 0408:7a10

        # --- Mobile Devices ---
        # Samsung Electronics Co., Ltd (MTP, ADB, PTP)
        allow id 04e8:*

        # Block everything else
        reject
      '';
      IPCAllowedUsers = [ "root" ];
    };
  };

  # ==========================================
  # HARDENING & AUDITING
  # ==========================================
  security = {
    # Explicitly disable Gnome Keyring in PAM for the greeter
    pam = {
      services = {
        cosmic-greeter.enableGnomeKeyring = false;

        # Enable Google Authenticator for SSH
        sshd.googleAuthenticator.enable = true;
        sshd.rules.auth.google-authenticator = {
          order = 11500; # After fprintd
          control = "sufficient";
          modulePath = "${pkgs.google-authenticator}/lib/security/pam_google_authenticator.so";
        };

        sudo.u2fAuth = true;
      };
    };

    # U2F / YubiKey Configuration (PAM level)
    pam.u2f = {
      enable = true;
      settings = {
        cue = true; # Prompt the user to touch the key
        authfile = config.sops.secrets.u2f_keys.path;
      };
    };

    apparmor = {
      enable = true;
      killUnconfinedConfinables = false;
    };
    audit = {
      enable = true;
      rules = [
        # Log all command executions (forensic trail)
        "-a exit,always -F arch=b64 -S execve"
        # Log changes to critical identity files
        "-w /etc/passwd -p wa -k identity"
        "-w /etc/shadow -p wa -k identity"
        "-w /etc/sudoers -p wa -k sudo_changes"
        # Log mount operations
        "-a always,exit -F arch=b64 -S mount -k mounts"
        # Zero Trust: Log firewall rule modifications
        "-a always,exit -F arch=b64 -S setsockopt -F a0=0 -k nftables_changes"
        # Zero Trust: Log container namespace creation
        "-a always,exit -F arch=b64 -S clone -F a0&0x7C020000 -k container_ns"
        "-a always,exit -F arch=b64 -S unshare -k namespace_creation"
      ];
    };
    auditd.enable = true;
    protectKernelImage = true;
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
        | ${pkgs.findutils}/bin/xargs -0 -r ${pkgs.clamav}/bin/clamdscan -c ${scanConfig} --multiscan --fdpass || true
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
    # Lynis Security Audit (Weekly)
    # ---------------------------
    services.lynis-audit = {
      description = "Lynis Security Audit";
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.lynis}/bin/lynis audit system --no-colors --quiet > /var/log/lynis-report.txt 2>&1
      '';
    };
    timers.lynis-audit = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
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

  # Prevent audit rule loading failures from blocking activation
  # (the kernel audit subsystem may be locked/busy during live switch;
  #  rules load correctly on next boot)
  systemd.services.audit-rules-nixos.serviceConfig.SuccessExitStatus = [ 1 ];

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
      "audit=1"
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
      "kernel.unprivileged_userns_clone" = 1;
    };
  };
}
