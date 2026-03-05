{ config, ... }:

{
  users.users.martin = {
    isNormalUser = true;
    linger = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "podman"
      "docker"
      "video"
      "render"
      "libvirtd"
      "kvm"
      "tss"
      "plugdev"
      "adbusers"
    ];
    hashedPasswordFile = config.sops.secrets.martin_password.path;
  };

  sops.secrets.martin_password = {
    neededForUsers = true;
  };
}
