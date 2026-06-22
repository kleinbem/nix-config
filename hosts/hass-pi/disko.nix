# hass-pi disko layout — Raspberry Pi 5 on native NVMe (PCIe HAT).
#
# No on-disk swap: hass-pi's job is to run Home Assistant, and all heavy
# builds now happen in CI (GitHub Actions + Attic cache), so the box only
# pulls prebuilt closures. Memory headroom is served by zram (core.nix,
# zramSwap memoryPercent=50) — faster and zero SSD wear. A dedicated
# encrypted swap partition only ever made sense for local kernel builds,
# which no longer happen here. If disk swap is ever needed again it must
# return as a *dedicated partition* (the "swap outside LUKS" rule rules out
# a btrfs swapfile inside hass_crypt).
{
  device ? "/dev/nvme0n1",
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
                name = "hass_crypt";
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
