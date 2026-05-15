{
  pkgs,
  lib,
  config,
  inputs,
  myInventory,
  ...
}:

let
  user = "martin";
  home = "/home/${user}";
  clamDir = "/var/lib/clamav";

  # Notification script that bridges systemd (root/clamav) -> user session (dbus)
  notifyScript = pkgs.writeShellScript "clamav-notify" ''
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
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
  # nix-mineral hardening module
  imports = [ inputs.nix-mineral.nixosModules.nix-mineral ];

  config = {

    # ==========================================
    # SMARTCARD (PKCS#11) CONFIGURATION
    # ==========================================

    # ==========================================
    # PERSISTENCE COMPATIBILITY FIXES
    # ==========================================

    # ==========================================
    # NIX-MINERAL — Standard Hardening
    # ==========================================
    nix-mineral = {
      enable = false; # Temporarily disabled due to nosuid root lockout
      preset = "compatibility"; # Best for desktop/workstation workloads
      settings = {
        # Custom overrides for workstation needs
        network.ip-forwarding = true; # Required for containers/bridges
        system.multilib = true; # Required for some development tools
      };
    };

    # ==========================================
    # HARDENING & SECURITY
    # ==========================================

    environment = {
      systemPackages = with pkgs; [
        clamav
        clamtk # GUI
        libnotify # For notifications
        lynis # Security auditing

        # Smartcard (PKCS#11 PIV)
        opensc
        yubico-piv-tool
        yubikey-manager
        apparmor-profiles # Pre-built profiles for ClamAV, Dnsmasq, etc.
      ];

      # Force the correct SSH_AUTH_SOCK for all sessions.
      # extraInit runs after PAM/Gnome Keyring, allowing us to enforce our agent.
      extraInit = ''
        export SSH_AUTH_SOCK="/run/user/$(id -u)/ssh-agent"
      '';

      sessionVariables = {
      };
    };

    programs.ssh = {
      # Start the standard OpenSSH agent system-wide (replaces HM service)
      startAgent = true;
      agentPKCS11Whitelist = "/nix/store/*-opensc-*/lib/opensc-pkcs11.so";
    };

    # Disable GNOME's GCR SSH Agent to prevent conflict with programs.ssh
    services = {
      pcscd.enable = true;

      openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "no";
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = true; # Required for MFA
          AuthenticationMethods = "publickey,keyboard-interactive"; # Require BOTH key AND code

          # Hardening per Lynis suggestions
          AllowTcpForwarding = "yes"; # Kept 'yes' for developer productivity/container setup
          AllowAgentForwarding = "no";
          ClientAliveCountMax = 2;
          MaxAuthTries = 3;
          MaxSessions = 2;
          TCPKeepAlive = "no";
        };
      };

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
          # Trust all SanDisk Corp. devices (Flash drives, SD readers)
          allow id 0781:*
          # Intel Bluetooth Adapter
          allow id 8087:0026
          # USB to SATA/PCIe Bridge (External Harddisk Reader)
          allow id 152d:0581
          # Generic USB2.0 Card Reader
          allow id 0bda:0153
          # ESS Technology USB DAC (Audio)
          allow id 0495:3048
          # USB 2.0 Hub
          allow id 05e3:0610
          # Terminus Technology Hubs (Nested in VIA units)
          allow id 1a40:0101
          allow id 1a40:0801
          # VIA Labs USB Hub (3.0 and 2.0 components)
          allow id 2109:0817
          allow id 2109:2817
          # Hub Internal Components (SD Reader & Ethernet)
          allow id 2537:1081
          allow id 0bda:8151
          # HD Camera
          allow id 0408:7090
          # Webcam USB Audio
          allow id 0408:7a10

          # --- Mobile Devices ---
          # Trust all Samsung Electronics Co., Ltd devices (MTP, ADB, Download Mode, etc.)
          allow id 04e8:*


          # Block everything else
          reject
        '';
        IPCAllowedUsers = [
          "root"
          "martin"
        ];
      };
    };

    # ==========================================
    # ENTERPRISE AI TEAM AIRLOCK (RBAC)
    # ==========================================
    # These rules enforce 'Least Privilege' at the network level on the host,
    # ensuring that agents can only communicate with approved upstream targets.
    networking.nftables.tables.ai-airlock = {
      family = "inet";
      content = ''
        chain forward {
          type filter hook forward priority filter; policy accept;

          # AI Agent Team -> LiteLLM & Langfuse
          ip saddr ${myInventory.network.nodes.agent-team.ip} ip daddr { ${myInventory.network.nodes.litellm.ip}, ${myInventory.network.nodes.langfuse.ip} } tcp dport { 4000, 3000 } accept
          
          # Bootstrap/Maintenance: Allow DNS and HTTPS temporarily for uv dependency sync
          ip saddr ${myInventory.network.nodes.agent-team.ip} udp dport 53 accept
          ip saddr ${myInventory.network.nodes.agent-team.ip} tcp dport { 53, 443 } accept

          # Block Agent Team from reaching the broader Internet or local network
          ip saddr ${myInventory.network.nodes.agent-team.ip} reject with icmpx type admin-prohibited
        }
      '';
    };

    # ==========================================
    # HARDENING & AUDITING
    # ==========================================
    security = {
      sudo.extraRules = [
        {
          users = [ "martin" ];
          commands = [
            {
              command = "${pkgs.nh}/bin/nh os switch";
              options = [ "NOPASSWD" ];
            }
            {
              command = "${pkgs.nh}/bin/nh os boot";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/nixos-rebuild";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/systemctl restart container@*";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/systemctl start ollama.service";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/systemctl stop ollama.service";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/systemctl restart ollama.service";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/systemctl start vllm.service";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/systemctl stop vllm.service";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/systemctl restart vllm.service";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
      # Explicitly disable Gnome Keyring in PAM for the greeter
      pam = {
        services = {
          gdm = {
            enableGnomeKeyring = true;
            u2fAuth = true;
          };
          login = {
            enableGnomeKeyring = true;
            u2fAuth = true;
          };

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
      protectKernelImage = true;

      # ==========================================
      # AUTHENTICATION HARDENING
      # ==========================================
      # Increase password hashing rounds (Lynis Suggestion AUTH-9230)
      loginDefs.settings = {
        SHA_CRYPT_MIN_ROUNDS = 100000;
        SHA_CRYPT_MAX_ROUNDS = 100000;
      };
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
        "d /var/log/security-audit 0775 root wheel - -"
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

    boot = {
      # Security & Performance Tweaks
      blacklistedKernelModules = [
        "pcspkr"
        "snd_pcsp"
      ];

      # Kernel parameters moved to kernel.nix for consolidation

      kernel.sysctl = {
        # ==========================================
        # AI-HARDENING COMPATIBILITY
        # ==========================================
        # Ensure unprivileged user namespaces are ENABLED (Nspawn needs them)
        # nix-mineral or other hardening might disable them by default.
        "kernel.unprivileged_userns_clone" = lib.mkForce 1;
        "kernel.perf_event_paranoid" = lib.mkForce 2;
        # ClamAV On-Access Scanning (essential for large directories)
        "fs.inotify.max_user_watches" = 524288;
      };
    };
  };
}
