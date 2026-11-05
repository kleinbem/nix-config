# Declarative LUKS+btrfs data disk at a fixed mountpoint. nixos-nvme unlocks
# it with FIDO2 in initrd; nasbook has no FIDO2 and opens it in stage 2 from
# a keyfile on the encrypted root (stage2KeyFile).
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
    # Never an initrd secret: the initrd sits on the unencrypted ESP.
    stage2KeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/nix/persist/etc/crypt/data.key";
      description = ''
        Keyfile on the already-unlocked root. When set, the disk is opened in
        stage 2 through /etc/crypttab instead of in the initrd, so it must not
        be neededForBoot.
      '';
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
            };
            # With false disko emits no unlock at all; the crypttab entry below does it.
            initrdUnlock = cfg.stage2KeyFile == null;
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

    # systemd-cryptsetup-generator already orders the unit after the keyfile's mount.
    environment.etc.crypttab = lib.mkIf (cfg.stage2KeyFile != null) {
      text = "${cfg.cryptName} /dev/disk/by-partlabel/disk-data-luks_data ${cfg.stage2KeyFile} ${
        lib.concatStringsSep "," ([ "luks" ] ++ cfg.crypttabExtraOpts)
      }\n";
    };
  };
}
