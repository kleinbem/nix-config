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
  # LUKS passphrase file for scripted provisioning (nasbook-install-usb);
  # null keeps the interactive prompt. Must stay a named arg: `...` would
  # swallow --argstr passwordFile silently.
  passwordFile ? null,
  ...
}:
{
  # ─── Stateless Root (Impermanence) ──────────────────────────
  # disko only declares /boot, /nix and /nix/persist, so / and /var are
  # tmpfs here; real state lives under /nix/persist via persistence.nix.
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
    # impermanence asserts every fileSystem backing environment.persistence
    # has neededForBoot — the disko-declared /nix/persist subvolume above
    # doesn't set it by default.
    "/nix".neededForBoot = true;
    "/nix/persist".neededForBoot = true;
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
                inherit passwordFile;
                settings = {
                  allowDiscards = true;
                  # No FIDO2 fallback on nasbook (unlike the other headless
                  # hosts) — unlock is Tang (silent) or the recovery
                  # passphrase/initrd SSH (my.boot.clevis-initrd, default.nix).
                  crypttabExtraOpts = [
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
