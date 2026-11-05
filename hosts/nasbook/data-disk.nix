# nasbook bulk-storage data disk — QNAP TBS-453A's second SSD bay.
# LUKS + btrfs at /mnt/data via my.dataDisk. No FIDO2 on this host: it opens
# in stage 2 from a keyfile on the Tang-unlocked root, like orin's Frigate SSD.
{ config, ... }:
{
  my.dataDisk = {
    enable = true;
    device = "/dev/disk/by-id/ata-SanDisk_SD8SN8U1T001122_163331421028";
    cryptName = "nasbook_data_crypt";
    crypttabExtraOpts = [
      "discard"
      "x-systemd.device-timeout=60s"
      "nofail"
    ];
    # Host-local, root-only (my.hostSecrets); sops copy via access::nasbook-data-backup.
    stage2KeyFile = "${config.my.hostSecrets.dir}/nasbook-data.key";
  };

  # nofail lets boot go on without the disk; these must not start on the
  # empty /mnt directory of the tmpfs root instead.
  systemd.services = {
    "container@paperless".unitConfig.RequiresMountsFor = [ "/mnt/data" ];
    "container@qbittorrent".unitConfig.RequiresMountsFor = [ "/mnt/data" ];
    restic-backups-bulk-gdrive.unitConfig.RequiresMountsFor = [ "/mnt/data" ];
    restic-backups-bulk-r2.unitConfig.RequiresMountsFor = [ "/mnt/data" ];
  };
}
