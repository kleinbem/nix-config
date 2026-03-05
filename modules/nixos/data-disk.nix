_:

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
