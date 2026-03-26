{
  device ? "/dev/sdc",
  ...
}:
let
  # Set this to a device path (e.g., "/dev/nvme1n1") when your 2nd SSD arrives
  frigateDevice = null;
in
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
                  # Auto-unlock with TPM2 if available, fallback to FIDO2/YubiKey
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
      if frigateDevice != null then
        {
          frigate = {
            device = frigateDevice;
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                frigate = {
                  size = "100%";
                  content = {
                    type = "filesystem";
                    format = "xfs";
                    mountpoint = "/mnt/frigate";
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
          root = {
            size = "128G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
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
