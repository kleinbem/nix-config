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
      "/var/lib/systemd/timesync" # NTP drift for faster syncing
      "/var/lib/udisks2" # Storage daemon state
      "/var/lib/upower" # Power management history
      "/var/lib/logrotate" # Log rotation state
      "/var/lib/images" # Container state (Caddy, n8n, databases, etc)
      "/var/lib/containers" # Podman/Docker containers
      "/var/lib/nixos-containers" # NixOS Containers (imperative/declarative roots)
      "/var/lib/machines" # systemd-machined and systemd-nspawn container state
      "/var/lib/syncthing" # Syncthing device identity and config
      "/var/lib/private/tang" # Tang NBDE keys (DynamicUser → /var/lib/private)
      "/var/lib/lxc" # LXC state
    ];
    files = [
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ]
    ++ lib.optional (!config.boot.initrd.systemd.enable) "/etc/machine-id";

    # Shell history survives reboots on edge devices with an ephemeral
    # root (hass-pi, and similar Pi/Jetson boxes) — without this it's
    # wiped every boot. Excludes nixos-nvme: its /home is a real, separate,
    # already-durable partition (/dev/vg0/home), so persisting through the
    # bind-mount indirection here is unnecessary — and actively breaks
    # activation the first time, since impermanence refuses to silently
    # pick a winner when a real file already sits at the target path with
    # no corresponding source under /nix/persist yet.
    users.martin = lib.mkIf (config.networking.hostName != "nixos-nvme") {
      files = [
        ".bash_history"
        ".zsh_history"
      ];
    };
  };

  # Impermanence mkdir -p creates parent directories (like /var/lib/private) with 0755.
  # This breaks systemd DynamicUser services (like tangd) which require 0700.
  systemd.tmpfiles.rules = [
    "d /var/lib/private 0700 root root - -"
    "d /nix/persist/var/lib/private 0700 root root - -"
  ];
}
