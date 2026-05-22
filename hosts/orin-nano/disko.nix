{
  device ? "/dev/sdc",
  secondDiskDevice ? "/dev/nvme1n1",
  ...
}:
{
  disko.devices = {
    disk = {
      main = {
        inherit device;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "orin_crypt";
                settings = {
                  allowDiscards = true;
                  crypttabExtraOpts = [
                    "tpm2-device=auto"
                    "fido2-device=auto"
                  ];
                };
                content = {
                  type = "lvm_pv";
                  vg = "vg_orin";
                };
              };
            };
          };
        };
      };
    }
    // (
      if secondDiskDevice != null then
        {
          second = {
            device = secondDiskDevice;
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                frigate = {
                  size = "100%";
                  content = {
                    type = "luks";
                    name = "orin_frigate_crypt";
                    settings = {
                      allowDiscards = true;
                      crypttabExtraOpts = [ "tpm2-device=auto" ];
                    };
                    content = {
                      type = "filesystem";
                      format = "xfs";
                      mountpoint = "/mnt/data/frigate";
                    };
                  };
                };
              };
            };
          };
        }
      else
        { }
    );
    lvm_vg = {
      vg_orin = {
        type = "lvm_vg";
        lvs = {
          nix = {
            size = "128G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/nix";
              mountOptions = [ "noatime" ];
            };
          };
          models = {
            size = "256G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/mnt/models";
            };
          };
          data = {
            size = "100%FREE";
            content = {
              type = "btrfs";
              subvolumes = {
                "data" = {
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
}
