{
  disko.devices = {
    disk = {
      nvme0n1 = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            # Windows MSR (you currently have 2x 16M; I'd just create 1)
            msr = {
              size = "16M";
              type = "0C01";
            };

            # Shared EFI System Partition
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };

            # Windows (placeholder; no formatting here)
            windows = {
              size = "100G";
              type = "0700";
            };

            # Windows Recovery (placeholder)
            winre = {
              size = "1G";
              type = "2700";
            };

            # Linux (everything else)
            luks = {
              size = "100%";
              type = "8300";
              content = {
                type = "luks";
                name = "cryptroot";
                settings.allowDiscards = true; # NVMe, usually fine
                content = {
                  type = "lvm_pv";
                  vg = "vg0";
                };
              };
            };
          };
        };
      };
    };

    lvm_vg = {
      vg0 = {
        type = "lvm_vg";
        lvs = {
          swap = {
            size = "16G";
            content = {
              type = "swap";
            };
          };

          root = {
            size = "60G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };

          var = {
            size = "120G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/var";
            };
          };

          nix = {
            size = "300G";
            content = {
              type = "filesystem";
              format = "btrfs";
              mountpoint = "/nix";
              mountOptions = [
                "noatime"
                "compress=zstd"
              ];
            };
          };

          images = {
            size = "800G";
            content = {
              type = "filesystem";
              format = "ext4"; # (optional: switch to btrfs if you want snapshots/compression)
              mountpoint = "/images";
              mountOptions = [ "noatime" ];
            };
          };

          home = {
            size = "400G";
            content = {
              type = "filesystem";
              format = "btrfs";
              mountpoint = "/home";
              mountOptions = [
                "noatime"
                "compress=zstd"
              ];
            };
          };
          # Intentionally leave ~100G unallocated in vg0 for future growth.
        };
      };
    };
  };
}
