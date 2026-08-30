{
  device ? "/dev/sdc",
  secondDiskDevice ? "/dev/nvme1n1",
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
              };
            };
            swap = {
              size = "16G";
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
                name = "orin_crypt";
                settings = {
                  allowDiscards = true;
                  crypttabExtraOpts = [
                    "fido2-device=auto"
                    "x-systemd.device-timeout=60s"
                  ];
                  # tpm2-device=auto removed: this Jetson exposes no /dev/tpm0.
                  # FIDO2 (YubiKey) is the interactive unlock method; Tang/clevis
                  # handles silent auto-unlock over the network.
                };
                content = {
                  type = "lvm_pv";
                  vg = "vg_orin";
                };
              };
            };
          };
        };
      };
    }
    // (
      if secondDiskDevice != null then
        {
          second = {
            device = secondDiskDevice;
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                frigate = {
                  size = "100%";
                  content = {
                    type = "luks";
                    name = "orin_frigate_crypt";
                    # The keyfile lives on /nix — i.e. INSIDE the clevis/Tang-unlocked
                    # orin_crypt root, which is not mounted during initrd. So this
                    # device cannot be unlocked in stage 1: initrdUnlock = false, and
                    # the stage-2 crypttab entry that actually opens it is declared in
                    # services.nix (disko emits nothing for the LUKS device itself when
                    # initrdUnlock is false). Leaving this at its default (true) wires
                    # an initrd luks.devices entry whose keyFile can never be read →
                    # unattended boot stalls on a passphrase prompt.
                    initrdUnlock = false;
                    settings = {
                      allowDiscards = true;
                      # Unlock using a keyfile stored on the main encrypted root.
                      # This avoids prompting for a password twice and fixes the TPM2 bug
                      # (Jetson has no /dev/tpm0). See the stage-2 crypttab in services.nix.
                      keyFile = "/nix/persist/etc/crypt/frigate.key";
                    };
                    content = {
                      type = "filesystem";
                      # ext4, not xfs: the L4T/Jetson kernel ships no XFS module
                      # ("unknown filesystem type 'xfs'" on mount). ext4 is what
                      # root uses here and is Frigate's own recommended fs.
                      format = "ext4";
                      mountpoint = "/mnt/data/frigate";
                      # nofail + short device timeout: this is a remote headless host,
                      # and a missing/failed second disk must never wedge boot or block
                      # anything that needs /mnt/data (the btrfs parent). noatime:
                      # this disk takes constant Frigate recording writes.
                      mountOptions = [
                        "nofail"
                        "noatime"
                        "x-systemd.device-timeout=15s"
                      ];
                    };
                  };
                };
              };
            };
          };
        }
      else
        { }
    );
    lvm_vg = {
      vg_orin = {
        type = "lvm_vg";
        lvs = {
          nix = {
            size = "128G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/nix";
              mountOptions = [ "noatime" ];
            };
          };
          models = {
            size = "256G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/mnt/models";
            };
          };
          data = {
            size = "100%FREE";
            content = {
              type = "btrfs";
              # block-group-tree (enabled by default in btrfs-progs ≥6.19) requires Linux 6.1+
              # Jetson kernel is older — disable it to avoid mount failures
              extraArgs = [
                "-O"
                "^block-group-tree"
              ];
              subvolumes = {
                "data" = {
                  mountpoint = "/mnt/data";
                  mountOptions = [
                    "compress=zstd"
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
}
