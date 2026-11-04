# mac-mini disko layout: Mid-2011 Mac Mini SATA SSD, provisioned over a
# USB-SATA adapter (mac-mini-install-usb), then moved inside.
# Swap sits outside LUKS with randomEncryption (fresh key every boot), so it
# needs no unlock. It only backs up zram.
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
