{ pkgs, ... }:

{
  # ==========================================
  # ANTIVIRUS (ClamAV)
  # ==========================================
  services.clamav = {
    daemon.enable = true;
    updater = {
      enable = true;
      interval = "daily"; # Check for updates daily
      frequency = 12; # Checks per day
    };
  };

  # Optional: Scanner utility
  environment.systemPackages = [ pkgs.clamav ];

  # ==========================================
  # SMART SCAN (Incremental)
  # ==========================================
  systemd.services.clamav-smart-scan = {
    description = "ClamAV Smart Scan (Recently Modified Files)";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      echo "🛡️ Starting ClamAV Smart Scan..."
      # Find files modified in the last 24 hours in home and scan them
      # Exclude various caches and dotfiles to speed it up
      ${pkgs.findutils}/bin/find /home/martin \
        -mtime -1 \
        -type f \
        -not -path "*/.cache/*" \
        -not -path "*/node_modules/*" \
        -not -path "*/.git/*" \
        -print0 | \
        ${pkgs.findutils}/bin/xargs -0 -r ${pkgs.clamav}/bin/clamdscan --multiscan --fdpass
    '';
  };

  systemd.timers.clamav-smart-scan = {
    description = "Run ClamAV Smart Scan nightly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
