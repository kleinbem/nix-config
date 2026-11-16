{
  pkgs,
  config,
  lib,
  ...
}:
let
  faillockRule = {
    enable = true;
    modulePath = "${config.security.pam.package}/lib/security/pam_faillock.so";
  };
  # Tally on disk (persisted): /var/run would reset the lockout on every reboot.
  faillockDir = "/var/lib/faillock";
  faillockArgs = [
    "deny=5"
    "unlock_time=300"
    "dir=${faillockDir}"
  ];
in
{
  options.my.security.loginNeedsPasswordAndKey = lib.mkEnableOption ''
    password plus YubiKey touch for local login (tty and GDM, incl. its lock screen).
    A touch alone never hands PAM a password, so the login keyring would stay locked'';

  config = {
    environment.systemPackages = with pkgs; [
      # Smartcard (PKCS#11 PIV)
      opensc
      yubico-piv-tool
      yubikey-manager
    ];

    services.pcscd.enable = true;
    # pcscd idle-exits after ~60s, so every YubiKey use after a pause is a new
    # start, and core.nix's 5-starts-per-15m default trips on normal sops use
    # ("Could not open YubiKey"). Safe to exempt: no Restart=, and the socket's
    # TriggerLimit still caps storms.
    systemd.services.pcscd.unitConfig.StartLimitIntervalSec = 0;
    programs.yubikey-touch-detector.enable = true;

    services.gnome = {
      gnome-keyring.enable = true;
      # Disable GNOME's GCR SSH Agent to prevent conflict with programs.ssh
      gcr-ssh-agent.enable = false;
    };

    programs.ssh.agentPKCS11Whitelist = "/nix/store/*,/run/current-system/*";

    security.pam = {
      services = {
        gdm = {
          enableGnomeKeyring = true;
          u2fAuth = true;
        };
        login = {
          enableGnomeKeyring = true;
          u2fAuth = true;
          # Second factor, not a replacement. nouserok: a missing sops authfile falls back
          # to the password instead of locking everyone out. sudo keeps touch-only.
          rules = lib.mkIf config.my.security.loginNeedsPasswordAndKey {
            auth = {
              u2f = {
                control = lib.mkForce "required";
                settings.nouserok = true;
              };
              # Lockout for a short password: 5 wrong tries lock the account for 5 minutes.
              faillock-preauth = faillockRule // {
                order = config.security.pam.services.login.rules.auth.u2f.order - 10;
                control = "requisite";
                args = [ "preauth" ] ++ faillockArgs;
              };
              faillock-authfail = faillockRule // {
                order = config.security.pam.services.login.rules.auth.unix.order + 10;
                control = "[default=die]";
                args = [ "authfail" ] ++ faillockArgs;
              };
            };
            # Resets the counter after a successful login.
            account.faillock = faillockRule // {
              order = config.security.pam.services.login.rules.account.unix.order - 10;
              control = "required";
              args = [ "dir=${faillockDir}" ];
            };
          };
        };
        sudo.u2fAuth = true;
        # Same tally and limits for the fingerprint login GDM offers alongside.
        gdm-fingerprint.rules.auth.faillock.settings =
          lib.mkIf (config.my.security.loginNeedsPasswordAndKey && config.services.fprintd.enable)
            {
              deny = 5;
              unlock_time = 300;
              dir = faillockDir;
            };
      };

      # U2F / YubiKey Configuration (PAM level)
      u2f = {
        enable = true;
        settings = {
          cue = true; # Prompt the user to touch the key
          authfile = config.sops.secrets.u2f_keys.path;
        };
      };
    };

    systemd.tmpfiles.rules = lib.mkIf config.my.security.loginNeedsPasswordAndKey [
      "d ${faillockDir} 0700 root root -"
    ];

    boot.initrd.systemd.storePaths = [ pkgs.pcsclite.lib ];
  };
}
