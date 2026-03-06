{ lib, ... }:

{
  disko.devices = {
    disk = {
      data = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            # Single LUKS encrypted partition taking the whole drive
            luks_data = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptdata";
                settings = {
                  allowDiscards = true;
                  crypttabExtraOpts = [ "fido2-device=auto" ];
                };
                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-L"
                    "data"
                  ];
                  subvolumes = {
                    "/" = {
                      mountpoint = "/mnt/data";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                        "nofail"
                      ];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # Workaround: Disko does not generate crypttab for non-boot disks when
  # boot.initrd.systemd.enable = true. We manually generate the crypttab entry
  # so that the main system's systemd-cryptsetup-generator unlocks the drive.
  environment.etc."crypttab".text = lib.mkDefault ''
    cryptdata /dev/disk/by-partlabel/disk-data-luks_data - fido2-device=auto,discard
  '';
}
