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
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    # Multi-container workstation: Increase backlog to prevent dropped events
    rules = [

      # --- Critical Identity & Access ---
      "-w /etc/passwd -p wa -k identity"
      "-w /etc/group -p wa -k identity"
      "-w /etc/shadow -p wa -k identity"
      "-w /etc/sudoers -p wa -k identity"
      "-w /etc/sudoers.d -p wa -k identity"

      # --- System Operations ---
      "-a always,exit -F arch=b64 -S mount -k mounts"
      "-a always,exit -F arch=b64 -S setsockopt -k nftables_changes" # Simplified for stability

      # --- Runtime Behavioral Monitoring (Worm & Malware Detection) ---
      # 1. Execution from Temporary / Shared Memory Directories
      "-w /tmp -p x -k tmp_exec"
      "-w /var/tmp -p x -k tmp_exec"
      "-w /dev/shm -p x -k shm_exec"

      # 2. 32-bit Execution (Often used by legacy malware/worms to bypass 64-bit eBPF/audit rules)
      "-a always,exit -F arch=b32 -S execve -k 32bit_exec"

      # 3. Unauthorized DNS & Hostname Modifications
      "-w /etc/resolv.conf -p wa -k dns_modification"
      "-w /etc/hosts -p wa -k dns_modification"
      "-a always,exit -F arch=b64 -S sethostname -S setdomainname -k sethostname"

      # 4. Kernel Module Loading / Rootkit Behavior
      "-w /sbin/insmod -p x -k kmod_change"
      "-w /sbin/rmmod -p x -k kmod_change"
      "-w /sbin/modprobe -p x -k kmod_change"
      "-a always,exit -F arch=b64 -S init_module -S delete_module -k kmod_change"

      # 5. Process Injection / Ptrace (Process Hollowing)
      "-a always,exit -F arch=b64 -S ptrace -k code_injection"

      # --- Sensitive File Access (Immutable Identity & Config) ---
      "-w /var/lib/sops -p r -k sops_read"
      "-w /etc/ssh -p wa -k sshd_config"
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
        scriptArgs = "%I";
        script = ''
          # Input format: "Title|Message|ReportPath"
          IFS='|' read -r TITLE MESSAGE REPORT <<< "$1"
          TOPIC="nixos-alerts-martin-${config.networking.hostName}"

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
      # NixOS Host Scan (Host + Data Volumes + Secrets + Lynis)
      # Unified Security Scan (Host + Data Volumes + Secrets + Lynis)
      vuln-scan = {
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
          ESCAPED=$(${config.systemd.package}/bin/systemd-escape "$TITLE|$MSG|HEARTBEAT")
          ${config.systemd.package}/bin/systemctl start "security-notify@$ESCAPED.service"
        '';
      };

      # Proactive Alerts: Notify on Home Manager failure
      "home-manager-${config.my.username}" = {
        unitConfig.OnFailure = "security-notify@HM\\x2dFailure\\x7cHome\\x2dManager\\x2dActivation\\x2dFailed\\x7cCHECK\\x2dLOGS.service";
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
