{ config, ... }:

{
  # Secrets are defined in host-specific secrets.nix to ensure correct ownership

  services.restic.backups.daily = {
    initialize = true;

    # Run as user to access User Rclone config and tokens
    user = config.my.username;

    # Repository: Rclone -> Google Drive (remote name 'gdrive')
    repository = "rclone:gdrive:backups/nixos";

    # Credentials
    passwordFile = config.sops.secrets.restic_password.path;
    rcloneConfigFile = config.sops.secrets.rclone_config.path;

    # Rate Limiting & Optimization
    extraOptions = [
      "rclone.args=\"--tpslimit 5 --fast-list --drive-chunk-size 64M\""
    ];

    # What to backup
    paths = [
      config.my.home
      "/var/lib/images/n8n" # n8n Container Data
    ];

    exclude = [
      # Cache & Temporary
      "${config.my.home}/.cache"
      "${config.my.home}/.local/share/Trash"
      "${config.my.home}/Downloads"

      # Cloud Drives (Mount Points) - IMPORTANT: Prevents infinite recursion!
      "${config.my.home}/GoogleDrive"
      "${config.my.home}/OneDrive"
      "${config.my.home}/Cloud"

      # Development - Build Artifacts
      "${config.my.home}/**/node_modules"
      "${config.my.home}/**/target"
      "${config.my.home}/**/result"
      "${config.my.home}/**/__pycache__"
      "${config.my.home}/**/.venv"

      # Large Repositories / AI Models (Already handled by Airlock pulls)
      "/**/*.qcow2"
      "/**/*.iso"
      "${config.my.home}/.local/share/containers"
      "${config.my.home}/ai-data"
      "/var/lib/images/vllm"
      "/var/lib/images/ollama"
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

  # --- Root-level System Backup (Critical Infrastructure) ---
  services.restic.backups.system = {
    initialize = false;
    user = "root"; # Run as root to access sensitive system files

    # Repository: Use a separate folder for system infrastructure
    repository = "rclone:gdrive:backups/nixos-system";

    # Credentials
    passwordFile = config.sops.secrets.restic_system_password.path;
    rcloneConfigFile = config.sops.secrets.rclone_config.path;

    # Rate Limiting & Optimization (Aggressive pacing for GDrive)
    extraOptions = [
      "rclone.args=\"--tpslimit 3 --fast-list --drive-chunk-size 128M\""
    ];

    # What to backup (Critical Infrastructure Only)
    paths = [
      "/etc/ssh" # Host Identity
      "/var/lib/sops" # Secret Decryption Keys
      "/nix/persist/var/lib/sbctl" # Lanzaboote/SecureBoot PKI
      "/var/lib/caddy" # SSL Certificates & State
      "/var/lib/images" # Container Persistent Volumes
    ];

    exclude = [
      "**/tmp"
      "**/.cache"
      "/var/lib/images/podman"
      "/var/lib/images/vllm"
      "/var/lib/images/ollama"
    ];

    pruneOpts = [
      "--keep-daily 14"
      "--keep-weekly 8"
      "--keep-monthly 12"
    ];

    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "2h";
    };
  };
}
