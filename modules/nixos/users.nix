{ config, lib, ... }:

{
  # ==========================================
  # USERS & SECURITY
  # ==========================================
  users = {
    mutableUsers = false;
    users = {
      root = {
        # Restoring sops-based password now that system is stable
        hashedPasswordFile = config.sops.secrets.root_password_hash.path;
      };
    };

    groups = {
      plugdev = { };
    };
  };

  # No unauthenticated initrd emergency shell: after a Tang unlock it would
  # hand anyone at the console the decrypted root, defeating Secure Boot.
  # Rescue is the initrd SSH on :2222, which needs a fleet hardware key.
  boot.initrd.systemd.emergencyAccess = false;

  sops.secrets.root_password_hash = {
    neededForUsers = true;
  };

  security = {
    # mkDefault so headless hosts (which set this to `false` for passwordless
    # sudo over SSH key-only access) can override without `lib.mkForce`.
    sudo.wheelNeedsPassword = lib.mkDefault true;
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
