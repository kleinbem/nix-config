# Declarative LUKS+btrfs data disk at a fixed mountpoint. nixos-nvme unlocks
# it with FIDO2 in initrd; nasbook has no FIDO2 and uses an initrd keyfile
# (hosts/nasbook/data-disk.nix).
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.dataDisk;
in
{
  options.my.dataDisk = {
    enable = lib.mkEnableOption "a declarative LUKS+btrfs data disk";
    device = lib.mkOption {
      type = lib.types.str;
      example = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7DNNJ0W123456";
      description = "Stable by-id path to the physical disk.";
    };
    cryptName = lib.mkOption {
      type = lib.types.str;
      default = "cryptdata";
      example = "cryptdata";
      description = "Mapped LUKS device name under /dev/mapper/.";
    };
    label = lib.mkOption {
      type = lib.types.str;
      default = "data";
      example = "data";
      description = "Filesystem label for the formatted btrfs volume.";
    };
    mountpoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/data";
      example = "/mnt/data";
      description = "Target filesystem directory mountpoint.";
    };
    crypttabExtraOpts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "fido2-device=auto" ];
      example = [ "fido2-device=auto" ];
      description = "Additional options passed to crypttab/initrd for LUKS unlock.";
    };
    # For hosts without FIDO2: a path embedded via boot.initrd.secrets (sops
    # isn't available in initrd). Sets boot.initrd.luks.devices' keyFile, not
    # disko's deprecated top-level one.
    keyFilePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/etc/secrets/initrd/data-disk.key";
      description = "Path to an initrd-embedded keyfile for non-interactive LUKS unlock.";
    };
  };

  config = lib.mkIf cfg.enable {
    disko.devices.disk.data = {
      type = "disk";
      inherit (cfg) device;
      content = {
        type = "gpt";
        partitions.luks_data = {
          size = "100%";
          content = {
            type = "luks";
            name = cfg.cryptName;
            settings = {
              allowDiscards = true;
              inherit (cfg) crypttabExtraOpts;
            }
            // (lib.optionalAttrs (cfg.keyFilePath != null) { keyFile = cfg.keyFilePath; });
            initrdUnlock = true;
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                cfg.label
              ];
              subvolumes."/" = {
                inherit (cfg) mountpoint;
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
}
