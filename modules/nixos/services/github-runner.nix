{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

let
  # Define the common build environment for OpenWrt and other projects
  commonBuildInputs = with pkgs; [
    # Core Build Tools
    git
    cachix
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
  # Ensure nix-shell works by linking nixpkgs to the system input
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  # ---------------------------------------------------------
  # GitHub Runners Service
  # ---------------------------------------------------------
  services.github-runners = {
    # Runner 1: OpenWrt Builder
    openwrt-builder = {
      enable = true;
      url = "https://github.com/kleinbem/openwrt-builder";
      # Token managed by sops
      tokenFile = config.sops.secrets.local_github_actions_runner.path;
      replace = true;
      name = "nixos-bpi-builder";

      # Labels allow you to select this specific runner in the workflow
      extraLabels = [
        "nixos"
        "openwrt"
        "filogic"
      ];

      # Bind the packages into the runner's path
      extraPackages =
        commonBuildInputs
        ++ (with pkgs; [
          podman
          shadow
        ]);

      # Hardening
      serviceOverrides = {
        ProtectHome = "read-only"; # Prevent runner from reading /home/martin
        PrivateDevices = false; # OpenWrt build might need loopback devices
        # CRITICAL: Allow runner to create User Namespaces (for bwrap/FHS)
        RestrictNamespaces = false;
        # Highly Recommended: prevent weird permission denails
        NoNewPrivileges = false;

        # Unlock Rootless Podman capabilities:
        PrivateUsers = false;
        ProtectKernelTunables = false;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];

        # Allow seeing processes (Required for Rootless Podman)
        ProtectProc = "default";
        ProcSubset = "all";

        # CRITICAL: Allow newuidmap to transition to root
        RestrictSUIDSGID = false;

        # Allow all capabilities (fixes newuidmap permission denied)
        CapabilityBoundingSet = lib.mkForce [ "~" ];
        AmbientCapabilities = lib.mkForce [ ];

        # NEW: Allow all system calls (needed for nested containers/bwrap)
        SystemCallFilter = lib.mkForce [ ];

        # Ensure we use the static 'github-runner' user for persistence
        DynamicUser = false;
        User = "github-runner";
        Group = "github-runner";
      };
    };
  };

  # ---------------------------------------------------------
  # Cleanup Service
  # ---------------------------------------------------------
  systemd.services.github-runner-cleanup = {
    description = "Cleanup GitHub Runner Workspace";
    startAt = "daily";
    serviceConfig = {
      Type = "oneshot";
      User = "github-runner";
      # Cleans the '_work' directory to preventing disk exhaustion.
      # Path assumes default state directory configuration: /var/lib/github-runners/<attr-name>
      ExecStart = "${pkgs.coreutils}/bin/rm -rf /var/lib/github-runners/openwrt-builder/_work";
    };
  };

  # ---------------------------------------------------------
  # User & Group Configuration
  # ---------------------------------------------------------
  users.users.github-runner = {
    isNormalUser = true;
    group = "github-runner";
    # REQUIRED for Rootless Podman/Docker:
    autoSubUidGidRange = true;
  };
  users.groups.github-runner = { };

  # ---------------------------------------------------------
  # Secrets Configuration
  # ---------------------------------------------------------
  sops.secrets.local_github_actions_runner = {
    owner = "github-runner"; # Must be readable by the service user
    # restartUnits = [ "github-runner-openwrt-builder.service" ]; # Restart runner if token changes
  };
}
