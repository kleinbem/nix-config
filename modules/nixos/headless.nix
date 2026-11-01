# Extra bits for headless/remote nodes (RPi5, NASbook, routers). Shared
# foundations live in base.nix.
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
    ./services/mesh-llm-gpu-runner.nix
  ];

  services = {
    # ─── mDNS (.local resolution on the LAN) ────────────────────
    avahi = {
      enable = true;
      nssmdns4 = true;
      settings.publish = {
        disable-publishing = false;
        publish-addresses = true;
        publish-workstation = true;
      };
    };

    # ─── SSH (headless tier) ────────────────────────────────────
    # Key-only, no MFA. Deliberately separate from security.nix's stricter
    # workstation tier (publickey + TOTP, no root); don't merge them.
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = lib.mkDefault "prohibit-password";
        PasswordAuthentication = false;
        # The 120s default runs from TCP accept and isn't reset by the FIDO2
        # PIN/touch prompt, so deploys that open several connections hit
        # "Timeout before authentication".
        LoginGraceTime = "300";
      };
    };

    # ─── Journal (tighter than core.nix's 4G default) ───────────
    # `settings` needs mkForce over core.nix; with `extraConfig` the lines
    # concatenate and journald takes the last duplicate key, so ours wins.
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
  # With `ssh -A`, sudo asks the forwarded agent for a YubiKey signature;
  # without an agent it falls back to the password. pam_rssh because
  # pam_ssh_agent_auth doesn't accept sk-ssh-ed25519 keys. Dedicated key
  # file: authorized_keys options are ignored here, so restricted automation
  # keys there would satisfy sudo too.
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
  # Reboot 10s after a panic or oops instead of hanging; pstore keeps the
  # trace. Set via sysctl, not the cmdline, so an early-boot panic halts
  # visibly instead of boot-looping.
  boot.kernel.sysctl = {
    "kernel.panic" = lib.mkDefault 10;
    "kernel.panic_on_oops" = lib.mkDefault 1;
  };
}
