_:

{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-WD_PC_SN740_SDDPTQE-2T00_23362K803042_1";
        content = {
          type = "gpt";
          partitions = {
            # Partition 1: Microsoft Reserved (MSR)
            MSR1 = {
              size = "16M";
              priority = 1;
            };
            # Partition 2: EFI System Partition (Shared)
            ESP = {
              size = "1G";
              priority = 2;
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            # Partition 3: Microsoft Reserved (MSR)
            MSR2 = {
              size = "16M";
              priority = 3;
            };
            # Partition 4: Windows (C:)
            Windows = {
              size = "100G";
              priority = 4;
            };
            # Partition 5: Windows Recovery
            Recovery = {
              size = "750M";
              priority = 5;
            };
            # Partition 6: Linux LUKS
            luks = {
              size = "100%"; # Takes the rest
              priority = 6;
              content = {
                type = "luks";
                name = "cryptroot";
                settings = {
                  allowDiscards = true;
                  crypttabExtraOpts = [
                    "fido2-device=auto"
                    "x-systemd.device-timeout=60s"
                    "password-echo=true"
                  ];
                };
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
          root = {
            size = "50G";
          };
          var = {
            size = "40G";
          };
          nix = {
            size = "300G";
            content = {
              type = "btrfs";
              subvolumes = {
                "/" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "noatime"
                    "compress=zstd:1"
                  ];
                };
                "/persist" = {
                  mountpoint = "/nix/persist";
                  mountOptions = [
                    "noatime"
                    "compress=zstd:1"
                  ];
                };
              };
            };
          };
          images = {
            size = "800G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/var/lib/images";
              mountOptions = [
                "nofail"
                "x-systemd.device-timeout=30s"
              ];
            };
          };
          swap = {
            size = "10G";
            content = {
              type = "swap";
            };
          };
          home = {
            size = "100%FREE";
            content = {
              type = "btrfs";
              mountpoint = "/home";
              mountOptions = [
                "noatime"
                "compress=zstd:1"
              ];
            };
          };
        };
      };
    };
  };
}
