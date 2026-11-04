{
  lib,
  pkgs,
  ...
}:
{
  # This is a slimmed-down version of your home config for Android
  home = {
    username = lib.mkForce "martin";
    homeDirectory = lib.mkForce "/data/data/com.termux.nix/files/home";
    stateVersion = "24.05";

    packages = [
      pkgs.herdr # client-only — attaches to the herdr server on nixos-nvme
    ];

    # `nvme` (ssh settings below) is the LAN IP, so this only works at home
    # until the phone joins NetBird (a manual step in the Android app).
    shellAliases.agents = "herdr --remote nvme";
  };

  # Only include terminal-based programs
  programs = {
    home-manager.enable = true;
    zsh.enable = true;
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    git = {
      enable = true;
      settings = {
        user = {
          name = "Martin";
          email = "your@email.com";
        };
      };
    };

    # nixos-nvme requires publickey+MFA (security/ssh.nix) for its normal
    # sshd; ControlMaster/ControlPersist reuse one authenticated connection
    # so repeat `agents` calls don't re-prompt for a Google Authenticator code.
    ssh = {
      enable = true;
      settings.nvme = {
        HostName = "10.0.0.5";
        User = "martin";
        ControlMaster = "auto";
        ControlPath = "~/.ssh/control-%C";
        ControlPersist = "4h";
        ServerAliveInterval = 60;
      };
    };
  };

  # Add any other phone-specific CLI tools here
}
