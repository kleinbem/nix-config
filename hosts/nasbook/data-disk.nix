# nasbook bulk-storage data disk — QNAP TBS-453A's second SSD bay.
#
# Previously a QNAP-formatted drive (mdadm RAID members); wiped 2026-09-18
# after Martin confirmed its data was already backed up elsewhere. Single
# LUKS-encrypted partition + btrfs, mounted at /mnt/data — same pattern as
# nixos-nvme's own data disk (modules/nixos/data-disk.nix, my.dataDisk.*).
#
# No FIDO2 on this host (see disko.nix) and this disk isn't needed for
# boot, so instead of adding another Tang/passphrase ceremony it unlocks
# silently via a keyfile embedded into initrd — same plain-file-in-
# kleinbem-secrets/initrd/ convention as the SSH host key and Tang JWE.
{ inputs, ... }:
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

  boot.initrd.secrets."/etc/nasbook-data.key" =
    inputs.kleinbem-secrets + "/initrd/data_luks_key_nasbook";

  # Same requirement disko.nix already documents for /nix and /nix/persist:
  # environment.persistence (impermanence) asserts every filesystem backing
  # a persisted path has neededForBoot — containers bind-mount paths under
  # /mnt/data (paperless, backup targets), so it's part of that chain too.
  fileSystems."/mnt/data".neededForBoot = true;
}
