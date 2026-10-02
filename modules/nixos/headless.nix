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
let
  sshKeys = (import ./keys.nix).ssh;
in
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
        # OpenSSH's 120s default was too short for FIDO2-SK auth against these
        # headless deploy targets: sshd's own LoginGraceTime timer runs
        # server-side from TCP accept, independent of and not reset by the
        # client's PIN-entry/touch prompt — a deploy tool opening several
        # sequential connections (nixos-rebuild --target-host/--build-host:
        # eval, build trigger, nix-copy-closure, activation) can lose the
        # race on any one of them if the human doesn't respond within the
        # window. Confirmed root cause 2026-09-20: repeated "Timeout before
        # authentication" in core-pi's sshd journal at the exact times both
        # `dev::apply` and `deployment::deploy` failed — a server-side
        # auth-timeout, not the "FIDO2/USB glitch" it was first misdiagnosed
        # as (usbreset + ssh-agent restart legitimately don't fix a timing
        # issue, which is exactly why both retry tiers in .just/dev.just's
        # apply recipe also failed identically). 300s gives real headroom
        # without meaningfully widening the unauthenticated-connection
        # window (SSH still refuses anything before a successful handshake).
        LoginGraceTime = "300";
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
  # in their own configuration (with keys.nix references). This block ensures
  # the user exists with the right groups and wires the sops password hash so
  # sudo authentication works with the fleet-shared password.
  users.users.${config.my.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = lib.mkDefault config.sops.secrets.martin_password.path;
  };

  sops.secrets.martin_password = {
    key = lib.mkDefault "martin_password_hash";
    neededForUsers = true;
  };

  # No blanket wheelNeedsPassword=false here: these are always-on,
  # network-facing hosts (core-pi fronts the public internet), so root
  # access is scoped through the fleet-wide per-command NOPASSWD allowlist
  # (security/sudo.nix, imported via core.nix) instead of unrestricted
  # passwordless sudo.

  # ─── Sudo with Hardware YubiKey (SSH Agent Forwarding) ──────
  # When connected via `ssh -A`, sudo authenticates by requesting a signature
  # from the forwarded SSH agent, requiring a physical tap on the local YubiKey
  # rather than typing a password. Falls back to password if no agent is forwarded.
  #
  # pam_rssh, not pam_ssh_agent_auth: the latter (0.10.x) predates OpenSSH's
  # security-key types, so it never accepted the sk-ssh-ed25519 keys this
  # fleet actually uses and always fell through to the password (2026-10-02).
  #
  # Dedicated key file, not /etc/ssh/authorized_keys.d: both modules skip
  # authorized_keys options, so a login-only `restrict,command=` automation
  # key (caddy-ca-refresh) or the no-touch signing key would also have
  # satisfied sudo. Only the touch-required FIDO2 keys may.
  security.pam = {
    rssh = {
      enable = true;
      settings.auth_key_file = "/etc/ssh/sudo_keys.d/$ruser";
    };
    services.sudo.rssh = true;
  };
  environment.etc."ssh/sudo_keys.d/${config.my.username}" = {
    mode = "0444";
    text = ''
      ${sshKeys.fido2}
      ${sshKeys.fido2-backup}
    '';
  };

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

  # ─── Unattended panic recovery ──────────────────────────────
  # Kernel default panic=0 hangs a headless box forever on a panic — nobody
  # is at the console. Reboot after 10s instead; efi_pstore (x86) has
  # already captured the trace by then, and systemd-pstore archives it into
  # the persisted /var/lib/systemd/pstore on the next boot. Treat an oops as
  # a panic too: a box that oopsed keeps running half-broken. Set via sysctl,
  # not the cmdline, so a panic in early boot still halts visibly instead of
  # boot-looping (see the panic=-1 note in security/hardening.nix).
  boot.kernel.sysctl = {
    "kernel.panic" = lib.mkDefault 10;
    "kernel.panic_on_oops" = lib.mkDefault 1;
  };
}
