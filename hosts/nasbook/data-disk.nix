# nasbook bulk-storage data disk — QNAP TBS-453A's second SSD bay.
# LUKS + btrfs at /mnt/data via my.dataDisk. No FIDO2 on this host, so it
# unlocks from a keyfile in initrd, generated on nasbook (my.hostSecrets).
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
    keyFilePath = "/etc/nasbook-data.key";
  };

  # Generated on nasbook (my.hostSecrets), never a store path.
  boot.initrd.secrets."/etc/nasbook-data.key" = "${config.my.hostSecrets.dir}/nasbook-data.key";

  # Same requirement disko.nix already documents for /nix and /nix/persist:
  # environment.persistence (impermanence) asserts every filesystem backing
  # a persisted path has neededForBoot — containers bind-mount paths under
  # /mnt/data (paperless, backup targets), so it's part of that chain too.
  fileSystems."/mnt/data".neededForBoot = true;
}
