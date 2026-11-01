# Shared disko layout for RPi5 nodes on NVMe: one LUKS+btrfs volume, no disk
# swap (zram is enough, they only pull closures; a swapfile inside LUKS is out).
# `luksName` has no default so two hosts can't silently share a volume name.
{
  device ? "/dev/nvme0n1",
  luksName,
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
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = luksName;
                settings = {
                  allowDiscards = true;
                  crypttabExtraOpts = [
                    "fido2-device=auto"
                    "x-systemd.device-timeout=60s"
                  ];
                };
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "compress=zstd:1"
                        "noatime"
                      ];
                    };
                    "/persist" = {
                      mountpoint = "/nix/persist";
                      mountOptions = [
                        "compress=zstd:1"
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
