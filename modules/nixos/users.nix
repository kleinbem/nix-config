{ pkgs, config, ... }:

{
  # ==========================================
  # USERS & SECURITY
  # ==========================================
  users = {
    users = {
      root = {
        hashedPasswordFile = config.sops.secrets.root-password-hash.path;
      };
    };

    groups = {
      # ollama = { };
      # open-webui = { };
      plugdev = { };
    };
  };

  sops.secrets.root-password-hash = {
    neededForUsers = true;
  };

  security = {
    sudo.wheelNeedsPassword = true;
    rtkit.enable = true;
    polkit.enable = true;
    pam.u2f = {
      enable = true;
      settings.cue = true;
    };
    tpm2.enable = true;
  };

  programs.fuse.userAllowOther = true;

  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };
}
