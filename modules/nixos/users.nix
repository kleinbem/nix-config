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

  # No unauthenticated stage-1 emergency shell. `true` here meant anyone at
  # the console got a root shell in the initrd whenever a unit failed —
  # after the Tang/TPM unlock, with the decrypted root in reach — which
  # undid Secure Boot (lanzaboote) on the workstation. Rescue path stays
  # the initrd SSH listener on :2222 (hardware-boot.nix / rpi5-node.nix),
  # which needs one of the fleet's hardware keys.
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
