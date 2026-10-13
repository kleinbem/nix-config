{
  pkgs,
  inputs,
  self,
  ...
}:

{
  # ─── Nix-on-Droid System Configuration for Tablet ─────────────
  imports = [
    "${self}/modules/nix-on-droid/dashboard.nix"
  ];

  system.stateVersion = "24.05";

  # ─── Terminal & Shell ─────────────────────────────────────────
  terminal.font = "${pkgs.fira-code}/share/fonts/opentype/FiraCode-Regular.otf";

  user.shell = "${pkgs.zsh}/bin/zsh";

  # ─── Environment ──────────────────────────────────────────────
  environment.packages = with pkgs; [
    # Core Utilities
    vim
    git
    htop
    btop
    openssh
    rsync
    curl
    wget
    tree
    ncurses
    which
  ];

  # ─── Home Manager Integration ────────────────────────────────
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    config =
      { ... }:
      {
        imports = [
          "${self}/users/martin/home-tablet.nix"
        ];
        home.stateVersion = "24.05";
      };
  };

  # ─── Nix Configuration ───────────────────────────────────────
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Pin the flake registry for faster offline lookups
  nix.registry = {
    nix-config.flake = self;
    nix-presets.flake = inputs.nix-presets;
    nix-devshells.flake = inputs.nix-devshells;
  };
}
