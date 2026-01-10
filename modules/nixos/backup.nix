{ config, ... }:

{
  # Define the secret for the Restic password
  sops.secrets.restic_password = {
    owner = "martin";
  };

  services.restic.backups.daily = {
    initialize = true;

    # Run as user to access User Rclone config and tokens
    user = "martin";

    # Repository: Rclone -> Google Drive (remote name 'gdrive')
    repository = "rclone:gdrive:backups/nixos";

    # Credentials
    passwordFile = config.sops.secrets.restic_password.path;
    rcloneConfigFile = "/home/martin/.config/rclone/rclone.conf";

    # What to backup
    paths = [
      "/home/martin"
      "/var/lib/n8n" # n8n Container Data
      # System paths like /etc/ssh or /var/lib/sops are not readable by 'martin'.
      # To backup those, we would need a separate root-level backup job
      # or ACL modifications. For now, we focus on user data.
    ];

    exclude = [
      # Cache & Temporary
      "/home/martin/.cache"
      "/home/martin/.local/share/Trash"
      "/home/martin/Downloads"

      # Cloud Drives (Mount Points) - IMPORTANT: Prevents infinite recursion!
      "/home/martin/GoogleDrive"
      "/home/martin/OneDrive"
      "/home/martin/Cloud" # Future location for cloud drives

      # Browsers & AI Caches
      "/home/martin/**/OptGuideOnDeviceModel"
      "/home/martin/**/SingletonLock"

      # Security - Skip Private Keys (User manages via YubiKey/Bitwarden)
      "/home/martin/.ssh/id_*" # Excludes private AND public keys (re-generatable)
      # Note: We keep .ssh/config and known_hosts as they are not sensitive

      # Development - Build Artifacts
      "/home/martin/**/node_modules"
      "/home/martin/**/target" # Rust
      "/home/martin/**/result" # Nix
      "/home/martin/**/__pycache__"
      "/home/martin/**/.venv" # Python venvs are reproducible
      "/home/martin/**/.gradle" # Java
      "/home/martin/**/.m2" # Maven

      # Application State (Reproducible/Large)
      "/home/martin/.local/share/flatpak" # Re-downloadable apps
      "/home/martin/.local/share/containers" # Podman images
      "/home/martin/.local/share/Docker" # Docker images
      "/home/martin/**/*.qcow2" # VM Images
      "/home/martin/**/*.iso" # ISOs
      "/home/martin/**/*.lock" # Optional: Lock files usually small, keep them.
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
