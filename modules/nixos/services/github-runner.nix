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
    # Runner: nix meta-workspace
    nix = {
      enable = true;
      ephemeral = true; # Auto-deregister after each job; avoids stale-credential failures
      url = "https://github.com/kleinbem/nix";
      tokenFile = config.sops.secrets.github_runner_pat.path;
      replace = true;
      name = "nixos-nvme-nix-v2";
      extraLabels = [
        "nixos"
        "reset-1"
      ];
      extraPackages = with pkgs; [
        git
        attic-client
      ];
      serviceOverrides = {
        DynamicUser = false;
        User = "github-runner";
        Group = "github-runner";
        Environment = [
          "NIX_SSL_CERT_FILE=/var/lib/caddy/ca-bundle.crt"
          "SSL_CERT_FILE=/var/lib/caddy/ca-bundle.crt"
        ];
      };
    };

    # Runner: nix-config
    nix-config = {
      enable = true;
      ephemeral = true; # Auto-deregister after each job; avoids stale-credential failures
      url = "https://github.com/kleinbem/nix-config";
      tokenFile = config.sops.secrets.github_runner_pat.path;
      replace = true;
      name = "nixos-nvme-nix-config-v2";
      extraLabels = [
        "nixos"
        "reset-1"
      ];
      extraPackages = with pkgs; [
        git
        attic-client
      ];
      serviceOverrides = {
        DynamicUser = false;
        User = "github-runner";
        Group = "github-runner";
        Environment = [
          "NIX_SSL_CERT_FILE=/var/lib/caddy/ca-bundle.crt"
          "SSL_CERT_FILE=/var/lib/caddy/ca-bundle.crt"
        ];
      };
    };

    # Runner: OpenWrt Builder
    openwrt-builder-v2 = {
      enable = true;
      ephemeral = true; # Auto-deregister after each job; avoids stale-credential failures
      url = "https://github.com/kleinbem/openwrt-builder";
      # Token managed by sops
      tokenFile = config.sops.secrets.github_runner_pat.path;
      replace = true;
      name = "nixos-bpi-builder-v2";

      # Labels allow you to select this specific runner in the workflow
      extraLabels = [
        "nixos"
        "openwrt"
        "filogic"
        "reset-1"
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
        ProtectHome = "read-only"; # Prevent runner from reading ${config.my.home}
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
        Environment = [
          "NIX_SSL_CERT_FILE=/var/lib/caddy/ca-bundle.crt"
          "SSL_CERT_FILE=/var/lib/caddy/ca-bundle.crt"
        ];
      };
    };
  };

  # Ensure runners wait for the network to be online
  systemd.services = {
    "github-runner-nix" = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };
    "github-runner-nix-config" = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };
    "github-runner-openwrt-builder-v2" = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    # ---------------------------------------------------------
    # Cleanup Service
    # ---------------------------------------------------------
    github-runner-cleanup = {
      description = "Cleanup GitHub Runner Workspaces";
      startAt = "daily";
      serviceConfig = {
        Type = "oneshot";
        User = "github-runner";
        ExecStart = "${pkgs.bash}/bin/bash -c 'rm -rf /var/lib/github-runners/nix/_work /var/lib/github-runners/nix-config/_work /var/lib/github-runners/openwrt-builder-v2/_work'";
      };
    };
  };

  # ---------------------------------------------------------
  # User & Group Configuration
  # ---------------------------------------------------------
  users.users.github-runner = {
    isNormalUser = true;
    group = "github-runner";
    # kvm: so CI nixosTest VMs (caddy-test, recovery-test, …) can use /dev/kvm.
    extraGroups = [ "kvm" ];
    # REQUIRED for Rootless Podman/Docker:
    autoSubUidGidRange = true;
  };
  users.groups.github-runner = { };

  # ---------------------------------------------------------
  # Secrets Configuration
  # ---------------------------------------------------------
  sops.secrets.github_runner_pat = {
    owner = "github-runner"; # Must be readable by the service user
    # restartUnits = [ "github-runner-openwrt-builder.service" ]; # Restart runner if token changes
  };
}
