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

  # Prevent /var/log/journal from growing indefinitely
  services.journald.extraConfig = "SystemMaxUse=1G";

  # Web-based System Administration
  # Web-based System Administration
  services.cockpit = {
    enable = true;
    port = 9091;
    openFirewall = true;
  };

  # Generic Boot Preferences
  boot.loader.timeout = 2; # Fast boot

  # Massive Swap (Essential for AI workloads)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
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
    # htop # Replaced by btop
    btop
    # unzip # Replaced by ouch
    # zip # Replaced by ouch
    ouch # Modern compression tool
    file
    pciutils

    # Modern CLI Tools
    gh # GitHub CLI
    just
    jq
    ripgrep
    fd
    eza # Modern ls replacement
    # tree # Replaced by eza --tree
    inputs.nh.packages.${pkgs.system}.default
    nix-output-monitor
    nvd

    # Nix Tooling
    nixfmt-rfc-style
    deadnix
    statix

    # Cockpit Tools
    pkgs.nur.repos.nikpkgs.cockpit-podman
    # pkgs.nur.repos.nikpkgs.cockpit-machines # Verify if present
    kexec-tools # Kernel Crash Dumps
    sosreport # System Analysis
  ];

  # Enable Kernel Crash Dumps (satisfies Cockpit Kdump check)
  boot.crashDump.enable = true;

  environment.sessionVariables = {
    FLAKE = "/home/martin/Develop/github.com/kleinbem/nix-config";
    NH_FLAKE = "/home/martin/Develop/github.com/kleinbem/nix-config"; # nh 4.2+ support
  };
}
