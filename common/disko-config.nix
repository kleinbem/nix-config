{
  disko.devices = {
    disk = {
      vdb = {
        type = "disk";
        device = "/dev/nvme0n1";
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
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                # Disable settings.keyFile if you want interactive password
                # settings.keyFile = "/tmp/secret.key";
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
            size = "10G";
            content = {
              type = "swap";
            };
          };
          root = {
            size = "50G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
          var = {
            size = "40G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/var";
            };
          };
          images = {
            size = "800G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/images";
            };
          };
          nix = {
            size = "300G";
            content = {
              type = "filesystem";
              format = "btrfs";
              mountpoint = "/nix";
            };
          };
          home = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "btrfs";
              mountpoint = "/home";
            };
          };
        };
      };
    };
  };
}
