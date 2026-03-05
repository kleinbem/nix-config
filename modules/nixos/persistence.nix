{
  inputs,
  ...
}:
{
  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

  environment.persistence."/nix/persist" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/tailscale"
      "/var/lib/sops"
      "/var/lib/NetworkManager"
      "/var/lib/fprint"
      "/var/lib/waydroid"
      "/var/lib/docker"
      "/var/lib/flatpak"
      "/var/lib/libvirt"
      "/var/lib/cups"
      "/var/lib/fwupd"
      "/var/lib/fail2ban"
      "/var/lib/usbguard"
      "/var/db/sudo"
      "/etc/NetworkManager/system-connections"
      # "/etc/cups"
      "/etc/waydroid-extra"
      "/var/lib/sbctl"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };

}
