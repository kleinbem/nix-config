{ modulesPath, lib, ... }:
{
  imports = [ "${modulesPath}/virtualisation/lxc-container.nix" ];

  # Incus manages the network interface 'eth0', we just need to use it.
  networking.useDHCP = false;
  networking.interfaces.eth0.useDHCP = true;

  # Don't try to manage the kernel or bootloader
  boot.loader.systemd-boot.enable = false;

  # Speed up boot by disabling documentation in containers
  documentation.enable = lib.mkForce false;
}
