# Declarative LUKS+btrfs data disk mounted at a fixed mountpoint. Shared
# between nixos-nvme (its own /mnt/data, FIDO2-unlocked in initrd — a
# desktop, YubiKey always available) and nasbook (its second SSD, no
# FIDO2 on that host — see hosts/nasbook/disko.nix — so it uses a keyfile
# embedded into initrd instead).
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
      description = "Stable by-id path to the physical disk.";
    };
    cryptName = lib.mkOption {
      type = lib.types.str;
      default = "cryptdata";
    };
    label = lib.mkOption {
      type = lib.types.str;
      default = "data";
    };
    mountpoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/data";
    };
    crypttabExtraOpts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "fido2-device=auto" ];
    };
    # A host with no FIDO2 unlock path (nasbook) should point this at a
    # path embedded into initrd via boot.initrd.secrets instead — same
    # plain-file-in-kleinbem-secrets/initrd/ convention as the fleet's SSH
    # host keys and Tang JWEs (sops secrets aren't available yet at initrd
    # time). Flows into the real (non-deprecated) boot.initrd.luks.devices
    # settings.keyFile NixOS option, not disko's own deprecated top-level one.
    keyFilePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {
    disko.devices.disk.data = {
      type = "disk";
      device = cfg.device;
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
                mountpoint = cfg.mountpoint;
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
