{ config, ... }:

{
  # ==========================================
  # USERS & SECURITY
  # ==========================================
  users = {
    users = {
      root = {
        # Restoring sops-based password now that system is stable
        hashedPasswordFile = config.sops.secrets.root-password-hash.path;
      };
    };

    groups = {
      plugdev = { };
    };
  };

  # Security: Disable unauthenticated stage-1 shell now that system boots correctly
  boot.initrd.systemd.emergencyAccess = true;

  sops.secrets.root-password-hash = {
    neededForUsers = true;
  };

  security = {
    sudo.wheelNeedsPassword = true;
    rtkit.enable = true;
    polkit = {
      enable = true;
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if ((action.id == "org.freedesktop.udisks2.encrypted-unlock-system" ||
               action.id == "org.freedesktop.udisks2.encrypted-unlock") &&
              subject.user == "martin") {
            return polkit.Result.YES;
          }
        });
      '';
    };
    tpm2.enable = true;
  };

  programs.fuse.userAllowOther = true;

}
