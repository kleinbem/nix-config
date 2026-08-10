{ config, ... }:

{
  users.users.martin = {
    isNormalUser = true;
    description = "Martin";
    linger = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "systemd-journal"
      "podman"
      "docker"
      "video"
      "render"
      "libvirtd"
      "kvm"
      "tss"
      "plugdev"
      "adbusers"
      "dialout"
    ];
    hashedPasswordFile = config.sops.secrets.martin_password.path;
  };

  sops.secrets.martin_password = {
    key = "martin_password_hash";
    neededForUsers = true;
  };
}
