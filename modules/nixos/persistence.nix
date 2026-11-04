{
  inputs,
  config,
  lib,
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
      "/var/lib/AccountsService" # GDM user list & per-user icons/realnames
      "/var/lib/sops"
      "/var/lib/NetworkManager"
      "/var/lib/fprint"
      # "/var/lib/waydroid"
      "/var/lib/docker"
      "/var/lib/flatpak"
      "/var/lib/libvirt"
      # /var/lib/caddy is a container hostDataDir — the container-host module
      # auto-derives its persistence entry; listing it here too trips
      # impermanence's duplicate-directory assertion.
      "/var/lib/cups"
      "/var/lib/fwupd"
      "/var/lib/fail2ban"
      "/var/lib/usbguard"
      "/var/db/sudo"
      "/etc/NetworkManager/system-connections"
      "/etc/secrets"
      # "/etc/waydroid-extra"
      "/var/lib/sbctl"
      # --- Added Missing Service & System State ---
      "/var/lib/netbird" # Identity and registration
      "/var/account" # Process accounting logs (Lynis/Security Audit)
      "/var/lib/systemd/backlight" # Screen brightness
      "/var/lib/systemd/rfkill" # Airplane mode state
      "/var/lib/systemd/timesync" # NTP drift for faster syncing (timesyncd legacy)
      "/var/lib/chrony" # Chrony drift and RTC calibration data
      "/var/lib/udisks2" # Storage daemon state
      "/var/lib/upower" # Power management history
      "/var/lib/logrotate" # Log rotation state
      "/var/lib/images" # Container state (Caddy, n8n, databases, etc)
      "/var/lib/containers" # Podman/Docker containers
      "/var/lib/nixos-containers" # NixOS Containers (imperative/declarative roots)
      "/var/lib/machines" # systemd-machined and systemd-nspawn container state
      "/var/lib/syncthing" # Syncthing device identity and config
      "/var/lib/private/tang" # Tang NBDE keys (DynamicUser → /var/lib/private)
      "/var/lib/systemd/pstore" # Kernel panic/oops dumps archived from EFI pstore — useless if lost on reboot
      "/var/lib/systemd/timers" # Persistent= timer stamps; without them catch-up after downtime never works
    ];
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      # /etc/machine-id deliberately absent: pinned on the kernel cmdline
      # instead (machine-id.nix) — impermanence can't bind it early enough
      # under systemd stage-1, which every host uses.
    ];

    # Keep shell history on ephemeral-root hosts. Not nixos-nvme: its /home is
    # a real partition, and impermanence fails activation when a real file
    # already sits at the target.
    users.martin = lib.mkIf (config.networking.hostName != "nixos-nvme") {
      files = [
        ".bash_history"
        ".zsh_history"
      ];
    };
  };

  # Impermanence mkdir -p creates parent directories (like /var/lib/private) with 0755.
  # This breaks systemd DynamicUser services (like tangd) which require 0700.
  systemd.tmpfiles.settings."10-impermanence-private" = {
    "/var/lib/private".d = {
      mode = "0700";
      user = "root";
      group = "root";
    };
    "/nix/persist/var/lib/private".d = {
      mode = "0700";
      user = "root";
      group = "root";
    };
  };

  # The /etc/ssh host key bind mount can be down while sops-install-secrets
  # runs during a switch, so point sops at the /nix/persist path directly.
  sops.age.sshKeyPaths = lib.mkOverride 900 [
    "/nix/persist/etc/ssh/ssh_host_ed25519_key"
  ];
}
