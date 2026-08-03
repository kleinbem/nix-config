# mac-mini disko layout — Mid-2011 Mac Mini, SATA SSD via USB-SATA adapter
# for provisioning (see .just/deployment.just mac-mini-install-usb), then
# moved internally. Same simple GPT/LUKS/btrfs shape as core-pi/hass-pi (no
# LVM — this box has no orin-style multi-volume storage need).
#
# On-disk swap partition, outside LUKS — same pattern as orin-nano's disko.nix.
# randomEncryption=true gives it a fresh random key every boot (discarded on
# shutdown), so nothing plaintext ever persists there and no Tang/FIDO2 unlock
# ceremony is needed for it, unlike the real root. 8G is a supplementary layer
# on top of zram (core.nix's memoryPercent=50 already gives ~8G compressed
# swap on this host's 16G RAM) — not the primary swap path.
{
  device ? "/dev/sdb",
  # Path to a file containing the LUKS passphrase, for non-interactive format
  # during scripted provisioning (mac-mini-install-usb generates a random
  # passphrase and writes it here instead of prompting). null preserves the
  # normal interactive cryptsetup prompt for manual/other-host use.
  passwordFile ? null,
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
            swap = {
              size = "8G";
              content = {
                type = "swap";
                discardPolicy = "both";
                randomEncryption = true;
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "mac_mini_crypt";
                inherit passwordFile;
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
