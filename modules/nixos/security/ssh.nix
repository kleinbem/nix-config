{ pkgs, ... }:
{
  environment.extraInit = ''
    export SSH_AUTH_SOCK="/run/user/$(id -u)/ssh-agent"
  '';

  programs.ssh = {
    # Start the standard OpenSSH agent system-wide (replaces HM service)
    startAgent = true;
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
