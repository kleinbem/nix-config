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
  boot.initrd.systemd.emergencyAccess = false;

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
    # Zero Trust: sudo requires YubiKey touch (hardware MFA)
    pam.services.sudo.u2fAuth = true;
    tpm2.enable = true;
  };

  programs.fuse.userAllowOther = true;

}
