# mac-mini disko layout — Mid-2011 Mac Mini, SATA SSD via USB-SATA adapter
# for provisioning (see .just/deployment.just mac-mini-install-usb), then
# moved internally. Same simple GPT/LUKS/btrfs shape as core-pi/hass-pi (no
# LVM — this box has no orin-style multi-volume storage need).
#
# No on-disk swap, same rationale as core-pi/hass-pi: CI+Attic supply
# prebuilt closures, zram covers memory headroom (core.nix). If the Zoom/
# recording container workload later proves swap-hungry, add a dedicated
# partition outside LUKS — don't put a swapfile inside mac_mini_crypt.
{
  device ? "/dev/sdb",
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
                name = "mac_mini_crypt";
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
