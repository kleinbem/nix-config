# rpi5-disko.nix — shared disko layout for RPi5 nodes on native NVMe (PCIe
# HAT), single LUKS+btrfs volume, no on-disk swap.
#
# Extracted 2026-09-11 from hosts/{core-pi,hass-pi}/disko.nix, which were
# byte-identical except the LUKS volume name — memory headroom on both hosts
# is served by zram (core.nix, zramSwap memoryPercent=50) instead, since all
# heavy builds happen in CI (GitHub Actions + Attic cache) and these boxes
# only pull prebuilt closures. If disk swap is ever needed again it must
# return as a *dedicated partition* (the "swap outside LUKS" rule rules out
# a btrfs swapfile inside the LUKS volume).
#
# `luksName` is required (no default) — every consumer must pick its own, to
# avoid two hosts silently sharing a LUKS volume name.
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
