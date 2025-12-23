{ config, pkgs, ... }:

{
  # ==========================================
  # USERS & SECURITY
  # ==========================================
  users.users.root = {
    initialPassword = "backup-root-password";
  };

  users.users.martin = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "podman"
      "video"
      "render"
      "libvirtd"
      "kvm"
    ];
    hashedPasswordFile = config.sops.secrets.martin_password.path;
  };

  # Required for password file
  sops.secrets.martin_password = {
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
  };

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
