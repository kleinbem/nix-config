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
      "/var/lib/incus"
      "/var/lib/docker"
      "/var/lib/flatpak"
      "/var/lib/libvirt"
      "/var/lib/cups"
      "/var/lib/fwupd"
      "/var/db/sudo"
      "/etc/NetworkManager/system-connections"
      "/etc/cups"
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

  # Security: Machine ID is used for system integrity
  # Machine-id must be exactly 32 chars.
  # Note: You can generate one with `dbus-uuidgen --ensure` if missing
}
