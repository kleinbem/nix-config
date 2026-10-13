{
  lib,
  pkgs,
  ...
}:
{
  # Slimmed-down Home Manager config for Huawei MatePad Pro (Android / Nix-on-Droid)
  home = {
    username = lib.mkForce "martin";
    homeDirectory = lib.mkForce "/data/data/com.termux.nix/files/home";
    stateVersion = "24.05";

    packages = with pkgs; [
      herdr # client-only — attaches to the herdr server on nixos-nvme
      ripgrep
      fd
      fzf
      jq
      starship
    ];

    shellAliases = {
      # 1-word shortcut to attach to live Herdr session over NetBird
      agents = "herdr --remote 100.117.212.232";
      herdr = "herdr --remote 100.117.212.232";

      # Fast fleet SSH shortcuts over NetBird WireGuard
      nvme = "ssh martin@100.117.212.232";
      corepi = "ssh martin@100.117.146.201";
      hass = "ssh martin@100.117.163.227";
      nas = "ssh martin@100.117.39.136";
    };
  };

  # Terminal-based programs
  programs = {
    home-manager.enable = true;
    zsh = {
      enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;
    };
    starship = {
      enable = true;
    };
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    git = {
      enable = true;
      settings.user = {
        name = "Martin Kleinberger";
        email = "martin.kleinberger@gmail.com";
      };
    };
  };
}
