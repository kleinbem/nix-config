{
  config,
  pkgs,
  ...
}:

let
  # Define the common build environment for OpenWrt and other projects
  commonBuildInputs = with pkgs; [
    # Core Build Tools
    git
    gnumake
    gcc
    binutils
    bzip2
    gzip
    unzip
    gnutar
    wget
    curl
    rsync
    patch
    diffutils
    findutils
    gawk
    file
    which

    # Libraries
    ncurses
    zlib
    openssl

    # Scripting
    perl
    python3
    python3Packages.setuptools # Critical for distutils

    # System
    util-linux
    procps
  ];
in
{
  # ---------------------------------------------------------
  # GitHub Runners Service
  # ---------------------------------------------------------
  services.github-runners = {
    # Runner 1: OpenWrt Builder
    openwrt-builder = {
      enable = true;
      url = "https://github.com/kleinbem/openwrt-builder";
      # Token managed by sops
      tokenFile = config.sops.secrets.github_runner_token_openwrt.path;
      replace = true;
      name = "nixos-bpi-builder";

      # Labels allow you to select this specific runner in the workflow
      extraLabels = [
        "nixos"
        "openwrt"
        "filogic"
      ];

      # Bind the packages into the runner's path
      extraPackages = commonBuildInputs;

      # Hardening
      serviceOverrides = {
        ProtectHome = "read-only"; # Prevent runner from reading /home/martin
        PrivateDevices = false; # OpenWrt build might need loopback devices
      };
    };
  };

  # ---------------------------------------------------------
  # User & Group Configuration
  # ---------------------------------------------------------
  users.users.github-runner = {
    isSystemUser = true;
    group = "github-runner";
  };
  users.groups.github-runner = { };

  # ---------------------------------------------------------
  # Secrets Configuration
  # ---------------------------------------------------------
  sops.secrets.github_runner_token_openwrt = {
    owner = "github-runner"; # Must be readable by the service user
    # restartUnits = [ "github-runner-openwrt-builder.service" ]; # Restart runner if token changes
  };
}
