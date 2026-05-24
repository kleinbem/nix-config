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
                  # tpm2-device=auto / fido2-device=auto removed: this Jetson exposes no
                  # /dev/tpm0 (no enrolled TPM/FIDO keyslot), so the initrd waited ~90s for
                  # a TPM that never appears and dropped to emergency mode before the
                  # passphrase fallback. Without them, boot prompts for the LUKS passphrase
                  # on the serial console. Re-add after enrolling a TPM2 keyslot on-device.
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
              # block-group-tree (enabled by default in btrfs-progs ≥6.19) requires Linux 6.1+
              # Jetson kernel is older — disable it to avoid mount failures
              extraArgs = [
                "-O"
                "^block-group-tree"
              ];
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
