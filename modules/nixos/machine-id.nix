{ config, lib, ... }:
# Pin /etc/machine-id on the kernel cmdline: with a tmpfs root, systemd needs
# it before impermanence's bind mounts exist, and a random id per boot loses
# journal history and changes the DHCP DUID. Derived from the hostname; not a
# secret. Override per host only to keep a pre-existing id.
{
  options.my.machineId = lib.mkOption {
    type = lib.types.strMatching "[0-9a-f]{32}";
    default = builtins.substring 0 32 (
      builtins.hashString "sha256" "kleinbem/machine-id/${config.networking.hostName}"
    );
    defaultText = lib.literalExpression ''
      builtins.substring 0 32 (builtins.hashString "sha256" "kleinbem/machine-id/''${config.networking.hostName}")
    '';
    description = "Pinned systemd machine-id (32 lowercase hex chars), passed as `systemd.machine_id=` on the kernel cmdline.";
  };

  config.boot.kernelParams = [ "systemd.machine_id=${config.my.machineId}" ];
}
