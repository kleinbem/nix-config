{ pkgs, config, ... }:

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
    pkgs.vulnix # NixOS Host
    pkgs.trivy # Podman/Docker Images
    pkgs.ntfy-sh # Remote notifications
    pkgs.libnotify # Desktop notifications (notify-send)
  ];

  systemd = {
    # Centralized Notification Script (Template)
    services = {
      "security-notify@" = {
        description = "Send Security Alert: %i";
        serviceConfig.Type = "oneshot";
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

      # NixOS Host Scan
      vuln-scan = {
        description = "Daily NixOS Vulnerability Scan (Vulnix)";
        serviceConfig.Type = "oneshot";
        script = ''
          REPORT="/var/log/vulnix-report.txt"
          echo "🔍 Starting NixOS Host Vulnerability Scan..."
          ${pkgs.vulnix}/bin/vulnix -S > "$REPORT" 2>&1 || true
          
          if grep -q "VULNERABILITY" "$REPORT"; then
            COUNT=$(grep -c "VULNERABILITY" "$REPORT")
            TITLE="Host-Vulnerabilities-Found"
            MSG="$COUNT-issues-found-in-NixOS-host"
            ${config.systemd.package}/bin/systemctl start "security-notify@$TITLE|$MSG|$REPORT.service"
          fi
        '';
      };

      # Podman Image Scan
      container-scan = {
        description = "Daily Podman Image Vulnerability Scan (Trivy)";
        serviceConfig = {
          Type = "oneshot";
          Environment = [ "TRIVY_CACHE_DIR=/var/cache/trivy" ];
        };
        script = ''
          REPORT="/var/log/trivy-report.txt"
          echo "🔍 Starting Podman Image Vulnerability Scan..."
          mkdir -p /var/cache/trivy
          ${pkgs.trivy}/bin/trivy image --all-images --format table --severity CRITICAL,HIGH --output "$REPORT" || true
          
          if [ -s "$REPORT" ] && grep -q "Total: [1-9]" "$REPORT"; then
            TITLE="Container-Vulnerabilities-Found"
            MSG="Critical-High-risks-detected-in-Podman"
            ${config.systemd.package}/bin/systemctl start "security-notify@$TITLE|$MSG|$REPORT.service"
          fi
        '';
      };

      # Daily Security Heartbeat
      security-heartbeat = {
        description = "Daily Security Status Heartbeat";
        serviceConfig.Type = "oneshot";
        script = ''
          HOST_REPORT="/var/log/vulnix-report.txt"
          CONT_REPORT="/var/log/trivy-report.txt"
          
          # Determine status
          STATUS="Healthy"
          if grep -q "VULNERABILITY" "$HOST_REPORT" || ( [ -s "$CONT_REPORT" ] && grep -q "Total: [1-9]" "$CONT_REPORT" ); then
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
      "f /var/log/vulnix-report.txt 0644 root root - -"
      "f /var/log/trivy-report.txt 0644 root root - -"
      "d /var/cache/trivy 0755 root root - -"
    ];
  };

  # Promtail: Ship logs to centralized Loki
  services.promtail = {
    enable = true;
    configuration = {
      server = {
        http_listen_port = 9080;
        grpc_listen_port = 0;
      };
      clients = [{
        url = "http://10.85.46.116:3100/loki/api/v1/push";
      }];
      scrape_configs = [
        {
          job_name = "system-security";
          static_configs = [{
            targets = [ "localhost" ];
            labels = {
              job = "security-audits";
              host = config.networking.hostName;
              __path__ = "/var/log/{vulnix,trivy}-report.txt";
            };
          }];
        }
        {
          job_name = "journal";
          journal = {
            max_age = "12h";
            labels = {
              job = "systemd-journal";
              host = config.networking.hostName;
            };
          };
          relabel_configs = [
            {
              source_labels = [ "__journal__systemd_unit" ];
              target_label = "unit";
            }
          ];
        }
      ];
    };
  };
}
