{ pkgs, ... }:

{
  programs = {
    bash = {
      enable = true;
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
        alias = {
          st = "status";
          co = "checkout";
          sw = "switch";
          br = "branch";
        };
        user = {
          name = "kleinbem";
          email = "martin.kleinberger@gmail.com";
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
  };

  # Init Starship Config
  xdg.configFile."starship.toml".source = ./files/starship.toml;

  home.packages = with pkgs; [
    fastfetch
    zellij # Terminal multiplexer
    yazi # Terminal file manager
    lazygit # Terminal git UI
  ];
}
