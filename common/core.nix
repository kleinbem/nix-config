{
  pkgs,
  inputs,
  ...
}:

{
  # ==========================================
  # NIX SETTINGS & CORE
  # ==========================================
  time.timeZone = "Europe/Dublin";
  i18n.defaultLocale = "en_IE.UTF-8";
  console.keyMap = "us";

  nixpkgs.config.allowUnfree = true;
  nix = {
    registry.nixpkgs.flake = inputs.nixpkgs;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      substituters = [ "https://cache.nixos.org" ];
      trusted-public-keys = [ "cache.nixos.org-1:Ik/ZBziETSRre3nCpv7l4WwhDD5OhoOx9LG/mIJV6Hg=" ];
      download-buffer-size = 1073741824;
      max-jobs = "auto";
      cores = 0;
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # ==========================================
  # CORE UTILITIES
  # ==========================================
  programs = {
    # Direnv for per-project environment loading
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    # Allow non-root users to mount FUSE
    fuse.userAllowOther = true;

    # Run unpatched binaries
    nix-ld.enable = true;
  };

  environment.systemPackages = with pkgs; [
    # Core Tools
    git
    curl
    wget
    htop
    btop
    unzip
    zip
    file
    pciutils

    # Modern CLI Tools
    just
    jq
    ripgrep
    fd
    tree
  ];
}
