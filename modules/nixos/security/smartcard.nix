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
  pinHashFile = config.my.security.loginPinHashFile;
  # pam_exec hands the typed secret on stdin, ended by a NUL. ARGV: hash file, u2f authfile.
  # No full KeyHandle,UserKey,CoseType,Options mapping for martin means pam_u2f's nouserok
  # may have skipped the touch: refuse the PIN then.
  checkPin = pkgs.writers.writePerl "login-pin-check" { } ''
    my $pin = do { local $/; <STDIN> } // "";
    $pin =~ s/\0.*//s;
    exit 1 unless ($ENV{PAM_USER} // "") eq "martin" && length $pin;
    open(my $keys, "<", $ARGV[1]) or exit 1;
    exit 1 unless grep { /^martin:[^\s,:]+,[^\s,:]+,[^\s,:]+,/ } <$keys>;
    open(my $fh, "<", $ARGV[0]) or exit 1;
    my $hash = <$fh> // "";
    $hash =~ s/\s+\z//;
    exit(($hash =~ /^\$y\$/ && (crypt($pin, $hash) // "") eq $hash) ? 0 : 1);
  '';
in
{
  options.my.security = {
    loginNeedsPasswordAndKey = lib.mkEnableOption ''
      password plus YubiKey touch for local login (tty and GDM, incl. its lock screen).
      A touch alone never hands PAM a password, so the login keyring would stay locked'';

    loginPinHashFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "^/[^[:space:]]+$");
      default = null;
      description = ''
        crypt(3) hash of a short PIN martin can log in with instead of his password (with
        loginNeedsPasswordAndKey, so the touch stays required). Login only; sudo ignores it.
        The login keyring then needs the PIN as its password.'';
    };
  };

  config = {
    assertions = [
      {
        assertion = pinHashFile == null || config.my.security.loginNeedsPasswordAndKey;
        message = "my.security.loginPinHashFile needs my.security.loginNeedsPasswordAndKey (the PIN must never work without the YubiKey touch).";
      }
      {
        assertion = pinHashFile == null || (config.security.pam.u2f.settings.authfile or null) != null;
        message = "my.security.loginPinHashFile needs security.pam.u2f.settings.authfile: the PIN check reads the key mappings from it.";
      }
    ];

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
          # requisite: without a touch, stop before any password or PIN is checked, so
          # guesses made without the key are never evaluated.
          rules = lib.mkIf config.my.security.loginNeedsPasswordAndKey {
            auth = {
              u2f = {
                control = lib.mkForce "requisite";
                settings.nouserok = true;
              };
              # Lockout for a short password: 5 wrong tries lock the account for 5 minutes.
              faillock-preauth = faillockRule // {
                order = config.security.pam.services.login.rules.auth.u2f.order - 10;
                control = "requisite";
                args = [ "preauth" ] ++ faillockArgs;
              };
              # Either the password or the PIN; a wrong one falls through to authfail.
              login-pin = lib.mkIf (pinHashFile != null) {
                order = config.security.pam.services.login.rules.auth.unix.order + 5;
                control = "sufficient";
                modulePath = "${config.security.pam.package}/lib/security/pam_exec.so";
                args = [
                  "quiet"
                  "expose_authtok"
                  "${checkPin}"
                  pinHashFile
                  config.security.pam.u2f.settings.authfile
                ];
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
