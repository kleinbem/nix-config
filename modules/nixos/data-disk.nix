_:

{
  disko.devices = {
    disk = {
      data = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WD_Red_SA500_2.5_2TB_2548TKD00121";
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
                  crypttabExtraOpts = [
                    "fido2-device=auto"
                    "discard"
                    "x-systemd.device-timeout=30s"
                    "nofail"
                  ];
                };
                initrdUnlock = true;
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
}
