{ lib, pkgs, ... }:
let
  keys = import ../keys.nix;
in
{
  environment.variables = {
    SSH_ASKPASS_REQUIRE = "force";
  };

  environment.extraInit = ''
    export SSH_AUTH_SOCK="/run/user/$(id -u)/ssh-agent"
  '';

  programs.ssh = {
    # Verify each host's initrd SSH (remote unlock) instead of trusting it on
    # first use: that's the moment a LUKS passphrase gets typed.
    knownHosts = lib.mapAttrs' (
      host: k:
      lib.nameValuePair "initrd-${host}" {
        hostNames = [
          "[${k.ip}]:2222"
          "[${host}]:2222"
        ];
        publicKey = k.key;
      }
    ) keys.initrdHostKeys;
    # Start the standard OpenSSH agent system-wide (replaces HM service)
    startAgent = true;

    # The agent gets the PIN dialog too, so a YubiKey key forwarded with
    # `ssh -A` can sign sudo on the fleet hosts (pam_rssh, headless.nix). The
    # NixOS default ties this to X11, and this desktop runs on Wayland.
    enableAskPassword = true;

    # Wrap lxqt-openssh-askpass to strip the trailing newline character
    # This prevents the "incorrect passphrase" error when entering FIDO2 PINs via the GUI!
    askPassword = "${pkgs.writeShellScript "ssh-askpass-clean" ''
      ${lib.getExe pkgs.lxqt.lxqt-openssh-askpass} "$@" | tr -d '\n'
    ''}";
  };

  # Logins use the key file directly (IdentityAgent none), so the YubiKey key
  # never reaches the agent on its own. Load its handle for `ssh -A` sudo;
  # adding it needs no PIN or touch, signing does.
  systemd.user.services.ssh-add-yubikey = {
    description = "Add the YubiKey SSH key to the agent";
    wantedBy = [ "default.target" ];
    after = [ "ssh-agent.service" ];
    requires = [ "ssh-agent.service" ];
    unitConfig.ConditionPathExists = "%h/.ssh/id_ed25519_sk";
    environment.SSH_AUTH_SOCK = "%t/ssh-agent";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe' pkgs.openssh "ssh-add"} %h/.ssh/id_ed25519_sk";
    };
  };

  services = {
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = true; # Required for MFA
        AuthenticationMethods = "publickey,keyboard-interactive"; # Require BOTH key AND code

        # Hardening per Lynis suggestions
        AllowTcpForwarding = "yes"; # Kept 'yes' for developer productivity/container setup
        AllowAgentForwarding = "no";
        ClientAliveCountMax = 2;
        MaxAuthTries = 3;
        MaxSessions = 2;
        TCPKeepAlive = "no";
      };
      extraConfig = ''
        # Allow key-only auth from NetBird mesh (WireGuard authenticated) and trusted local LAN
        Match Address 100.117.0.0/16,10.0.0.0/16
          AuthenticationMethods publickey
      '';
    };

    fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "1h";
      bantime-increment = {
        enable = true;
        maxtime = "168h"; # 1 week max for repeat offenders
      };
      jails.sshd = {
        settings = {
          enabled = true;
          port = "ssh";
          filter = "sshd";
          maxretry = 3;
        };
      };
    };
  };

  security.pam.services = {
    # Enable Google Authenticator for SSH
    sshd.googleAuthenticator.enable = true;
    sshd.rules.auth.google-authenticator = {
      order = 11500; # After fprintd
      control = "sufficient";
      modulePath = "${pkgs.google-authenticator}/lib/security/pam_google_authenticator.so";
    };
  };
}
