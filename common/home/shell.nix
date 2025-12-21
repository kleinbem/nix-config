{ pkgs, ... }:

{
  programs = {
    bash = {
      enable = true;
      shellAliases = {
        ll = "ls -l";
        update = "nh os switch";
        cleanup = "nh clean all";
        hm-logs = "journalctl -xeu home-manager-martin.service";
      };
    };

    starship = {
      enable = true;
      settings = {
        add_newline = false;
      };
    };

    git = {
      enable = true;
      aliases = {
        st = "status";
        co = "checkout";
        sw = "switch";
        br = "branch";
      };
      settings = {
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
