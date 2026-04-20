{
  pkgs,
  config,
  lib,
  myInventory,
  ...
}:

let
  lokiHost = myInventory.network.nodes.loki.ip;

  # nix-security-audit is now defined globally in scripts.nix as an overlay
in
{
  # ==========================================
  # KERNEL AUDIT SUBSYSTEM
  # ==========================================
  security.audit = {
    enable = true;
    # Multi-container workstation: Increase backlog to prevent dropped events
    rules = [
      "-b 8192"
      "-f 1"
      "-r 0"

      # --- Critical Identity & Access ---
      "-w /etc/passwd -p wa -k identity"
      "-w /etc/shadow -p wa -k identity"
      "-w /etc/sudoers -p wa -k sudo_changes"

      # --- System Operations ---
      "-a always,exit -F arch=b64 -S mount -k mounts"
      "-a always,exit -F arch=b64 -S setsockopt -k nftables_changes" # Simplified for stability

      # --- Zero-Trust & Behavioral Auditing (Now handled by Falco) ---
      # Redundant rules (memfd_create, ptrace, namespaces) have been removed
      # to prevent log duplication and CPU overhead.

      # --- Sensitive File Access (Immutable Identity & Config) ---
      "-w /var/lib/sops -p r -k sops_read"
      "-w /etc/ssh/sshd_config -p wa -k sshd_config"
    ];
  };

  # ==========================================
  # VULNERABILITY SCANS (VULNIX & TRIVY)
  # ==========================================
  environment.systemPackages = [
    # pkgs.vulnix # Deprecated in favor of unified Trivy auditing
    pkgs.trivy # Podman/Docker Images + NixOS Host FS
    pkgs.gitleaks # Secret scanning
    pkgs.ntfy-sh # Remote notifications
    pkgs.libnotify # Desktop notifications (notify-send)
  ];

  systemd = {
    # Centralized Notification Script (Template)
    services = {
      "security-notify@" = {
        description = "Send Security Alert: %i";
        serviceConfig = {
          Type = "oneshot";
          # Hardening
          ProtectSystem = "full";
          ProtectHome = "read-only";
          PrivateTmp = true;
          NoNewPrivileges = true;
          MemoryDenyWriteExecute = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
        };
        scriptArgs = "%i";
        script = ''
          # Input format: "Title|Message|ReportPath"
          IFS='|' read -r TITLE MESSAGE REPORT <<< "$1"
          TOPIC="nixos-alerts-martin-$(hostname)"

          echo "📢 Sending Alert: $TITLE - $MESSAGE"

          # 1. Desktop Notification
          USER_ID=$(id -u ${config.my.username})
          export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus"

          ${pkgs.sudo}/bin/sudo -u ${config.my.username} DISPLAY=:0 \
            DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS \
            ${pkgs.libnotify}/bin/notify-send -u critical "$TITLE" "$MESSAGE" || true

          # 2. Remote Notification (ntfy.sh)
          ${pkgs.curl}/bin/curl -d "$MESSAGE. Report: $REPORT" "ntfy.sh/$TOPIC" || true
        '';
      };

      # NixOS Host Scan (Unified Trivy)
      # NixOS Host Scan (Hybrid approach)
      # Unified Security Scan (Host + Data Volumes + Secrets + Lynis)
      vul-scan = {
        description = "Daily Security Audit (Unified)";
        serviceConfig = {
          Type = "oneshot";
          # Hardening
          ProtectSystem = "full";
          ProtectHome = "read-only";
          PrivateTmp = true;
          NoNewPrivileges = true;
          # nix-security-audit needs some privileges for lynis/trivy
        };
        script = ''
          ${pkgs.nix-security-audit}/bin/nix-security-audit all
        '';
      };

      # Podman Image Scan
      container-scan = {
        description = "Daily Podman Image Vulnerability Scan";
        serviceConfig = {
          Type = "oneshot";
          Environment = [ "TRIVY_CACHE_DIR=/var/cache/trivy" ];
          # Hardening
          ProtectSystem = "full";
          ProtectHome = "read-only";
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
        script = ''
          ${pkgs.nix-security-audit}/bin/nix-security-audit containers
        '';
      };

      # Daily Security Heartbeat
      security-heartbeat = {
        description = "Daily Security Status Heartbeat";
        serviceConfig = {
          Type = "oneshot";
          # Hardening
          ProtectSystem = "full";
          ProtectHome = "read-only";
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
        script = ''
          HOST_REPORT="/var/log/security-report-host.txt"
          CONT_REPORT="/var/log/security-report-containers.txt"

          # Determine status
          STATUS="Healthy"
          if ( [ -s "$HOST_REPORT" ] && grep -E "Total: [1-9]|HIGH:|CRITICAL:" "$HOST_REPORT" ) || \
             ( [ -s "$CONT_REPORT" ] && grep -E "Total: [1-9]|HIGH:|CRITICAL:" "$CONT_REPORT" ); then
            STATUS="Issues-Detected"
          fi

          TITLE="Daily-Heartbeat"
          MSG="$STATUS-Checked-Host-and-Containers"
          ${config.systemd.package}/bin/systemctl start "security-notify@$TITLE|$MSG|HEARTBEAT.service"
        '';
      };
    };

    timers = {
      security-heartbeat = {
        description = "Daily Security Heartbeat Timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "1h"; # Avoid bursty alerts
        };
      };
      vuln-scan = {
        description = "Daily NixOS Vulnerability Scan Timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
      container-scan = {
        description = "Daily Podman Vulnerability Scan Timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    };

    # Ensure log files and cache exist with correct permissions
    tmpfiles.rules = [
      "f /var/log/security-report-host.txt 0644 root root - -"
      "f /var/log/security-report-containers.txt 0644 root root - -"
      "f /var/log/lynis-report.txt 0644 root root - -"
      "d /var/cache/trivy 0755 root root - -"
      "d /var/log/audit 0750 root root - -" # Ensure directory exists for auditd
    ];
  };

  # Fluent Bit: Lightweight log shipping to centralized Loki
  services.fluent-bit = lib.mkForce {
    enable = true;
    settings = {
      service = {
        flush = 1;
        daemon = "off";
        log_level = "info";
        http_server = "on";
        http_listen = "0.0.0.0";
        http_port = 2020;
        health_check = "on";
      };
      pipeline = {
        inputs = [
          {
            name = "tail";
            path = "/var/log/security-report-host.txt,/var/log/security-report-containers.txt,/var/log/lynis-report.txt";
            tag = "security_audits";
          }
          {
            name = "tail";
            path = "/var/log/security-report-secrets.json";
            tag = "secret_scans";
          }
          {
            name = "tail";
            path = "/var/log/audit/audit.log";
            tag = "auditd_logs";
          }
          {
            name = "systemd";
            tag = "systemd_journal";
            read_from_tail = "on";
            strip_underscores = "on";
          }
        ];
        outputs = [
          {
            name = "loki";
            match = "security_audits";
            host = lokiHost;
            port = 3100;
            labels = "job=security-audits, host=${config.networking.hostName}";
            line_format = "json";
          }
          {
            name = "loki";
            match = "auditd_logs";
            host = lokiHost;
            port = 3100;
            labels = "job=auditd, host=${config.networking.hostName}";
            line_format = "json";
          }
          {
            name = "loki";
            match = "secret_scans";
            host = lokiHost;
            port = 3100;
            labels = "job=secret-scans, host=${config.networking.hostName}";
            line_format = "json";
          }
          {
            name = "loki";
            match = "systemd_journal";
            host = lokiHost;
            port = 3100;
            labels = "job=systemd-journal, host=${config.networking.hostName}";
            line_format = "json";
            remove_keys = "SYSLOG_IDENTIFIER,_HOSTNAME";
            # Dynamic labels for systemd units in newer Loki plugin
            label_keys = "$SYSTEMD_UNIT";
          }
        ];
      };
    };
  };

  # Ensure fluent-bit can read the systemd journal and audit logs
  users.groups.systemd-journal.members = [ "fluent-bit" ];
  users.groups.audit.members = [ "fluent-bit" ]; # Required for auditd logs access
}
