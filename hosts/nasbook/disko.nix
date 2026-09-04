# nasbook disko layout — QNAP TBS-453A NAS
#
# NAS storage setup with /mnt/data for large-capacity storage (archives, backups, etc.)
# Root filesystem on primary device with LUKS encryption.
#
# Device parameters:
#   device = "/dev/sda"    (primary OS drive)
#
# NOTE: Data drives (RAID arrays, additional HDDs) should be configured separately
# via ZFS/mdadm and mounted at /mnt/data. This layout only handles the OS drive.
# See: https://wiki.nixos.org/wiki/ZFS or https://wiki.nixos.org/wiki/RAID
{
  lib,
  device ? "/dev/sda",
  ...
}:
{
  # ─── Stateless Root (Impermanence) ──────────────────────────
  # disko only mounts /boot, /nix, /nix/persist above — it never defined
  # a root filesystem (a longstanding gap, only surfaced once an unrelated
  # journald assertion stopped masking it; nasbook likely hasn't rebuilt
  # since the hardware-configuration.nix→disko migration). Matches the
  # RPi5 (rpi5-node.nix) / nixos-nvme (hardware-boot.nix) pattern: real
  # state lives under /nix/persist via persistence.nix, bind-mounted back
  # in by hostname-agnostic module — see default.nix's import of it.
  fileSystems = {
    "/" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=2G"
        "mode=755"
      ];
      neededForBoot = true;
    };
    "/var" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=2G"
        "mode=755"
      ];
      neededForBoot = true;
    };
  };
  disko.devices = {
    disk = {
      primary = {
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
                name = "nasbook_crypt";
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
