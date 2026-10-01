{ config, lib, ... }:
# Stable /etc/machine-id for every host, pinned via the kernel cmdline.
#
# Every host runs a tmpfs root (persistence.nix) under systemd stage-1, where
# impermanence can't persist /etc/machine-id — systemd needs it before the
# bind mounts exist. Without a pin, systemd mints a random id each boot:
# "Detected first boot" every time, a fresh /var/log/journal/<id>/ per boot so
# `journalctl -b -1` / `--list-boots` never see past the current boot, and a
# DHCP DUID that changes on every reboot. Found 2026-10-01 while chasing
# nasbook's hard resets — 13 orphaned journal dirs, no boot history.
#
# Default is derived from the hostname so new hosts are covered with no
# per-host edit. Not a secret: nix-config is public and the value is on
# /proc/cmdline anyway. Override per host only to keep a pre-existing id.
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
