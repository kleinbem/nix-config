_:

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
  # Since /nix/persist is a subvolume, snapper will create .snapshots inside it.
}
