{ config, ... }:

{
  # Define the secret for the Restic password
  sops.secrets.restic_password = {
    owner = config.my.username;
  };

  services.restic.backups.daily = {
    initialize = true;

    # Run as user to access User Rclone config and tokens
    user = config.my.username;

    # Repository: Rclone -> Google Drive (remote name 'gdrive')
    repository = "rclone:gdrive:backups/nixos";

    # Credentials
    passwordFile = config.sops.secrets.restic_password.path;
    rcloneConfigFile = config.sops.secrets.rclone_config.path;

    # What to backup
    paths = [
      config.my.home
      "/var/lib/n8n" # n8n Container Data
      # System paths like /etc/ssh or /var/lib/sops are not readable by 'martin'.
      # To backup those, we would need a separate root-level backup job
      # or ACL modifications. For now, we focus on user data.
    ];

    exclude = [
      # Cache & Temporary
      "${config.my.home}/.cache"
      "${config.my.home}/.local/share/Trash"
      "${config.my.home}/Downloads"

      # Cloud Drives (Mount Points) - IMPORTANT: Prevents infinite recursion!
      "${config.my.home}/GoogleDrive"
      "${config.my.home}/OneDrive"
      "${config.my.home}/Cloud" # Future location for cloud drives

      # Browsers & AI Caches
      "${config.my.home}/**/OptGuideOnDeviceModel"
      "${config.my.home}/**/SingletonLock"

      # Security - Skip Private Keys (User manages via YubiKey/Bitwarden)
      "${config.my.home}/.ssh/id_*" # Excludes private AND public keys (re-generatable)
      # Note: We keep .ssh/config and known_hosts as they are not sensitive

      # Development - Build Artifacts
      "${config.my.home}/**/node_modules"
      "${config.my.home}/**/target" # Rust
      "${config.my.home}/**/result" # Nix
      "${config.my.home}/**/__pycache__"
      "${config.my.home}/**/.venv" # Python venvs are reproducible
      "${config.my.home}/**/.gradle" # Java
      "${config.my.home}/**/.m2" # Maven

      # Application State (Reproducible/Large/Restricted)
      "${config.my.home}/.local/share/flatpak" # Re-downloadable apps
      "${config.my.home}/.local/share/containers" # Podman images
      "${config.my.home}/.local/share/Docker" # Docker images
      "${config.my.home}/.local/share/waydroid" # Waydroid (Permission issues)
      "${config.my.home}/ai-data" # AI Data (Permission issues)
      "${config.my.home}/n8n-data" # n8n Data (Permission issues)
      "/**/*.qcow2" # VM Images
      "/**/*.iso" # ISOs
      "/**/*.lock" # Optional: Lock files usually small, keep them.
    ];

    # Pruning (Retention Policy)
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];

    # Health checks
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
