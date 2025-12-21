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
      };
    };

    starship = {
      enable = true;
      settings = {
        add_newline = true;
        scan_timeout = 10;
        character = {
          success_symbol = "[➜](bold green)";
          error_symbol = "[✗](bold red)";
        };
        directory = {
          truncation_length = 0;
          truncate_to_repo = false;
        };
        git_status = {
          disabled = false;
          ignore_submodules = true;
        };
      };
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
  };

  home.packages = [ pkgs.fastfetch ];
}
