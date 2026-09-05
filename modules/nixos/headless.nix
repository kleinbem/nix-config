# headless.nix — extra bits for headless/remote nodes (RPi5, NASbook, routers).
#
# Foundational settings (Nix config, locale, fleet trust chain, sops-nix,
# my.* schema, common overlays) live in `base.nix`. This file adds only the
# host-class-specific concerns:
#   - Tang clevis import
#   - Headless-tier SSH (key-only)
#   - Tight journald limits for storage-constrained nodes
#   - mDNS publishing
#   - A non-root user with sudo
#   - Silent kernel boot
#   - Container TUI (`lazydocker`) — headless hosts run all the containers
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
{
  imports = [
    ./services/tang.nix
  ];

  services = {
    # ─── mDNS (.local resolution on the LAN) ────────────────────
    avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };

    # ─── SSH (headless tier) ────────────────────────────────────
    # Key-only SSH for headless nodes (RPi nodes, NASbook, routers).
    # This is the LOOSER of two SSH tiers in this repo:
    #   - This (headless): publickey only — no MFA, since headless nodes
    #     can't easily prompt for keyboard-interactive challenges.
    #   - `security.nix` (workstation/server): publickey + keyboard-interactive
    #     MFA (Google Authenticator), no root, stricter limits.
    # The two configs are deliberately separate; do not consolidate without
    # accounting for the different security postures.
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = lib.mkDefault "prohibit-password";
        PasswordAuthentication = false;
      };
    };

    # ─── Journal (tighter than core.nix's 4G default) ───────────
    # core.nix sets SystemMaxUse=4G for workstations. RPi nodes / routers
    # have tighter storage, so we override with a smaller cap.
    #
    # New nixpkgs: `settings.Journal` is an attrset, so overriding core.nix's
    # SystemMaxUse needs mkForce. Old pin: `extraConfig` is types.lines, which
    # concatenates and lets journald take the last duplicate key, so our value
    # wins on hosts that load both without a force. See core.nix for why both
    # branches exist.
    journald =
      if options.services.journald ? settings then
        {
          settings.Journal = {
            SystemMaxUse = lib.mkForce "256M";
            MaxRetentionSec = "1month";
          };
        }
      else
        {
          extraConfig = ''
            SystemMaxUse=256M
            MaxRetentionSec=1month
          '';
        };
  };

  # ─── User ───────────────────────────────────────────────────
  # Hosts that need SSH access add `users.users.${config.my.username}.openssh.authorizedKeys.keys`
  # in their own configuration (with keys.nix references). This block just
  # ensures the user exists with the right groups.
  users.users.${config.my.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  security.sudo.wheelNeedsPassword = false;

  # ─── Container TUI ──────────────────────────────────────────
  # Headless hosts run nspawn / podman containers (AI services, Frigate,
  # paperless, etc). `lazydocker` is the TUI for inspecting them.
  environment.systemPackages = [ pkgs.lazydocker ];

  # ─── Silent Boot ────────────────────────────────────────────
  boot.kernelParams = [
    "quiet"
    "loglevel=3"
    "systemd.show_status=auto"
    "rd.udev.log_level=3"
  ];
}
