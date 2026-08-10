{ pkgs, ... }:

{
  # Snapper for automated snapshots of the persistence layer
  services.snapper = {
    snapshotInterval = "hourly";
    cleanupInterval = "daily";
    configs = {
      persist = {
        SUBVOLUME = "/nix/persist";
        ALLOW_USERS = [ "martin" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        # Retention policy
        TIMELINE_MIN_AGE = 1800; # 30 mins
        TIMELINE_LIMIT_HOURLY = 10;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_WEEKLY = 4;
        TIMELINE_LIMIT_MONTHLY = 6;
        TIMELINE_LIMIT_YEARLY = 0;
      };
    };
  };

  # Ensure the subvolume is ready for snapper
  # Snapper requires the subvolume to have a .snapshots directory or be a subvolume itself.
  systemd.services.snapper-init-persist = {
    description = "Initialize snapper .snapshots subvolume for persist";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      # Check if it's a btrfs subvolume. If not, and it's an empty dir, delete and create it.
      if [ ! -d "/nix/persist/.snapshots" ]; then
        ${pkgs.btrfs-progs}/bin/btrfs subvolume create /nix/persist/.snapshots
      elif ! ${pkgs.btrfs-progs}/bin/btrfs subvolume show /nix/persist/.snapshots >/dev/null 2>&1; then
        rmdir /nix/persist/.snapshots 2>/dev/null && ${pkgs.btrfs-progs}/bin/btrfs subvolume create /nix/persist/.snapshots || echo ".snapshots is not a subvolume and cannot be removed"
      fi
    '';
  };
}
