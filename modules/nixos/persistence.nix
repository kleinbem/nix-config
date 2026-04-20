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
      "/etc/waydroid-extra"
      "/var/lib/sbctl"
      "/etc/ssh"

      # --- Added Missing Service & System State ---
      "/var/lib/netbird" # Identity and registration
      "/var/lib/github-runners" # GitHub Actions runner state
      "/var/account" # Process accounting logs (Lynis/Security Audit)
      "/var/lib/systemd/backlight" # Screen brightness
      "/var/lib/systemd/rfkill" # Airplane mode state
      "/var/lib/systemd/timesync" # NTP drift for faster syncing
      "/var/lib/udisks2" # Storage daemon state
      "/var/lib/upower" # Power management history
      "/var/lib/logrotate" # Log rotation state
      "/var/lib/images" # Container state (Caddy, n8n, databases, etc)
    ];
    files = [
    ];
  };

}
