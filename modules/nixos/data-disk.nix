_:

{
  disko.devices = {
    disk = {
      data = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            # Single LUKS encrypted partition taking the whole drive
            luks_data = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptdata";
                settings = {
                  allowDiscards = true;
                  crypttabExtraOpts = [ "fido2-device=auto" ];
                };
                initrdUnlock = false;
                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-L"
                    "data"
                  ];
                  subvolumes = {
                    "/" = {
                      mountpoint = "/mnt/data";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                        "nofail"
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

  # Let systemd's cryptsetup-generator automatically create the service from crypttab
  environment.etc.crypttab = {
    mode = "0600";
    text = ''
      cryptdata /dev/disk/by-partlabel/disk-data-luks_data none fido2-device=auto,discard,x-systemd.device-timeout=30s
    '';
  };
}
