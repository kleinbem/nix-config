{ pkgs, ... }:

{
  programs = {
    bash = {
      enable = true;
      initExtra = ''
        export SSH_AUTH_SOCK=/run/user/$UID/ssh-agent
      '';
      shellAliases = {
        ls = "eza --icons";
        ll = "eza -l --icons --git";
        tree = "eza --tree --icons";
        update = "nh os switch";
        cleanup = "nh clean all";
        hm-logs = "journalctl -xeu home-manager-martin.service";

        # System Control
        os = "just --justfile ~/.justfile";
      };
    };

    starship = {
      enable = true;
    };

    git = {
      enable = true;
      settings = {
        user = {
          name = "kleinbem";
          email = "martin.kleinberger@gmail.com";
          signingKey = "/home/martin/.ssh/id_ed25519_sk.pub";
        };

        commit.gpgsign = true;
        gpg.format = "ssh";
        "gpg \"ssh\"".program = "${pkgs.openssh}/bin/ssh-keygen";

        alias = {
          st = "status";
          co = "checkout";
          sw = "switch";
          br = "branch";
        };
      };
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    fzf = {
      enable = true;
      enableBashIntegration = true;
    };

    bat.enable = true; # Syntax highlighting for cat

    # Smarter cd
    zoxide = {
      enable = true;
      enableBashIntegration = true;
    };

    delta = {
      enable = true;
    };

    zellij = {
      enable = true;
      enableBashIntegration = true;
      settings = {
        theme = "tokyo-night";
      };
    };

    lazygit = {
      enable = true;
      settings = {
        gui.theme = {
          lightTheme = false;
          activeBorderColor = [
            "green"
            "bold"
          ];
          inactiveBorderColor = [ "white" ];
          selectedLineBgColor = [ "reverse" ];
        };
      };
    };

    ssh = {
      enable = true;
      matchBlocks = {
        "*" = {
          addKeysToAgent = "yes";
        };
        "github.com" = {
          user = "git";
          identityFile = "/home/martin/.ssh/id_ed25519_sk";
        };
      };
    };

  };

  # Fix for YubiKey Git Signing (Gnome Keyring doesn't support FIDO2/SK keys well)
  services.ssh-agent.enable = true;

  # Init Starship Config
  xdg.configFile."starship.toml".source = ./files/starship.toml;

  # Manage Justfile declaratively
  # Manage Justfile declaratively
  home = {
    file = {
      ".justfile".source = ./files/justfile;
    };

    sessionVariables = {
      TERMINAL = "cosmic-terminal";
      # Ensure SSH asks for passphrase via GUI
      SSH_ASKPASS = "${pkgs.seahorse}/libexec/seahorse/ssh-askpass";
      SSH_ASKPASS_REQUIRE = "prefer";

      # Force use of standard ssh-agent (fixes YubiKey signing)
      # Gnome Keyring interferes with FIDO2/SK keys
      SSH_AUTH_SOCK = "/run/user/1000/ssh-agent";
      # Or if seahorse is not the right path, maybe try:
      # SSH_ASKPASS = "${pkgs.gnome.seahorse}/libexec/seahorse/ssh-askpass";
    };

    packages = with pkgs; [
      fastfetch
      yazi # Terminal file manager
      rclone
    ];
  };

  # Rclone needs a writable config to update tokens, so we copy it from secrets
  systemd.user.services.setup-rclone-config = {
    Unit = {
      Description = "Setup Rclone Config from Secrets";
      After = [ "sops-nix.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/mkdir -p %h/.config/rclone && ${pkgs.coreutils}/bin/cp -f /run/secrets/rclone_config %h/.config/rclone/rclone.conf && ${pkgs.coreutils}/bin/chmod 600 %h/.config/rclone/rclone.conf'";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
