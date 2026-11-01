{
  pkgs,
  inputs,
  lib,
  config,
  options,
  secretFile,
  ...
}:
let
  keys = import ./keys.nix;

  # waypipe 0.11.0's video path doesn't build against current ffmpeg (its
  # bindings use removed AVVulkanDeviceContext fields). Remote GUI debug
  # doesn't need it.
  waypipe-novideo = pkgs.waypipe.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dwith_video=disabled" ];
  });
in
{
  imports = [
    # Wraps nix-index/nix-locate with the prebuilt weekly database, so the
    # command-not-found hook works without ever running `nix-index` locally.
    inputs.nix-index-database.nixosModules.default
    # Per-command NOPASSWD allowlist, fleet-wide so headless hosts get scoped
    # root access instead of wheelNeedsPassword=false.
    ./security/sudo.nix
    # Lynis sysctl baseline + module blacklist for every host; the
    # hardening tier (security/hardening.nix) layers nix-mineral on top.
    ./security/sysctl.nix
  ];

  # ==========================================
  # NIX SETTINGS & CORE
  # ==========================================

  # With mutableUsers=true, hashedPasswordFile only applies when a user is
  # first created, so sops password changes never land. Users without a
  # declared password (root on headless hosts) get password login locked.
  users.mutableUsers = false;

  time.timeZone = "Europe/Dublin";
  i18n.defaultLocale = "en_IE.UTF-8";
  console.keyMap = "uk";

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate =
        pkg:
        builtins.elem (lib.getName pkg) [
          "vscode-extension-anthropic-claude-code"
          "claude-code"
          "ollama-cuda"
          "cuda_cudart"
          "cuda_cccl"
          "cuda_nvcc"
        ]
        || (lib.hasPrefix "cuda" (lib.getName pkg));
    };
  };
  nix = {
    registry.nixpkgs.flake = inputs.nixpkgs;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
        "auto-allocate-uids"
        "cgroups"
      ];
      auto-allocate-uids = true;
      extra-system-features = [ "uid-range" ];
      auto-optimise-store = true;
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
        "https://anduril.cachix.org"
        "https://cache.nixos-cuda.org"
        "https://cache.kleinbem.dev/system"
      ];
      trusted-public-keys = keys.upstreamCaches ++ [
        "system:dCe+aNk1+Dwf3IG6OVBKcf5h0oL0hkRVqYiLN7iOJhU="
        keys.binaryCache.kleinbem-fleet-build
      ];
      # Signs local builds so `nix copy --from ssh://<host>` on a sibling
      # accepts them (see keys.nix). Empty until the secret is deployed.
      secret-key-files = lib.optional (
        config.sops.secrets ? nix_signing_key
      ) config.sops.secrets.nix_signing_key.path;
      download-buffer-size = 1073741824;

      # Binary Cache Optimization
      builders-use-substitutes = true;
      connect-timeout = 20; # Increased to avoid falling back to source on slow connections
      # we actually want to wait longer if the issue is just slow connection
      # to avoid building from source.

      log-lines = 25;
      min-free = 1073741824; # 1GB
      max-jobs = 3;
      cores = 6; # Leave at least 2 cores free for the host GUI
      trusted-users = [
        "@wheel"
      ];
    };
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
    # Pull in the GitHub access token via sops, but only on hosts that
    # actually provision the secret. `if/then/else` keeps the path lookup
    # lazy so this module stays universally importable.
    extraOptions =
      if config.sops.secrets ? github_read_all_token then
        "!include ${config.sops.secrets.github_read_all_token.path}"
      else
        "";
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # Fleet build-signing key, for nix.settings.secret-key-files above.
  sops.secrets.nix_signing_key = {
    sopsFile = secretFile "nix/shared-signing.yaml";
    mode = "0400";
    owner = "root";
  };

  # ==========================================
  # PKI CERTIFICATES (Fleet Trust Chain)
  # ==========================================
  # Root CA of the caddy container fronting cache.kleinbem.dev; CI trusts the
  # same file. A recreated caddy mints a new CA: refresh this from
  # /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt on its
  # host, or the whole fleet fails TLS against the cache.
  security.pki.certificateFiles = [ ../../pki/caddy-root.crt ];

  services = {
    xserver.xkb.layout = "gb";

    # 4G: 1G rotated out in under a day on the workstation. headless.nix sets
    # less. Newer nixpkgs replaced `extraConfig` with `settings.Journal`;
    # handle both until every pin has `settings`.
    journald =
      if options.services.journald ? settings then
        { settings.Journal.SystemMaxUse = "4G"; }
      else
        { extraConfig = "SystemMaxUse=4G"; };

    # = hardware monitoring =
    smartd.enable = true;
    fwupd.enable = true;

    # Mobile Device Support
    gvfs.enable = true; # MTP/PTP support for file transfer

    # FHS dynamic executable compatibility for /bin and /usr/bin.
    # Resolves paths like /usr/bin/google-chrome, /usr/bin/env, /bin/bash dynamically.
    envfs.enable = true;

    # earlyoom is the RAM guard. It only fires when free memory AND free swap
    # are both low, and zram keeps MemAvailable looking healthy, so slow swap
    # exhaustion is left to systemd-oomd below.
    earlyoom = {
      enable = true;
      # m=10: kill at 10% free memory, s=10: kill at 10% free swap
      # --prefer: browser sub-processes (safe to restart)
      # --ignore: GUI and shell (keep system interactive)
      extraArgs = [
        "-m"
        "10"
        "-s"
        "10"
        "--prefer"
        "^(chrome|chromium)$"
        "--ignore"
        "^(gnome-shell|Xwayland|bash|zsh|antigravity.*)$"
      ];
    };
  };

  # systemd-oomd is the swap guard. Without the slices below it monitors no
  # cgroups; with them, past 90% swap it kills the cgroup using the most swap.
  systemd = {
    oomd = {
      enable = true;
      enableRootSlice = true;
      enableSystemSlice = true;
      enableUserSlices = true;
    };

    # Prevent broken services from restarting 1,000 times silently:
    # Trips the burst limit after 5 failures in 15 minutes, transitioning the unit
    # into a terminal "failed" state so monitoring and alerts can fire.
    settings.Manager = {
      DefaultStartLimitIntervalSec = "15m";
      DefaultStartLimitBurst = 5;
    };
    user.settings.Manager = {
      DefaultStartLimitIntervalSec = "15m";
      DefaultStartLimitBurst = 5;
    };
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
    # Allow non-root users to mount FUSE
    fuse.userAllowOther = true;

    # Run unpatched binaries
    nix-ld.enable = true;
    nix-ld.libraries = with pkgs; [
      zlib
      zstd
      stdenv.cc.cc
      curl
      openssl
      attr
      libssh
      bzip2
      libxml2
      acl
      libsodium
      util-linux
      xz
      systemd
      glib
      gtk3
      libuuid
      icu
      libuv
      stdenv.cc.cc.lib
    ];

    # Command Discovery (command-not-found alternative)
    nix-index.enable = true;
  };

  environment.systemPackages =
    with pkgs;
    [
      # Core Tools
      git
      curl
      wget
      btop
      ouch
      file
      pciutils

      # Modern CLI Tools
      # gh # Removed temporarily to fix aarch64 cross-compilation failure (unrecognized option '-m64' via CGO)
      just
      jq
      ripgrep
      fd
      eza
      nh
      nix-output-monitor
      nvd

      # Nix Tooling
      nixfmt
      deadnix
      statix
      manix # Fast terminal search for Nix/NixOS/HM options

      android-tools # ADB & Fastboot
      lm_sensors # Hardware heat sensors
    ]
    ++ lib.optionals (pkgs.stdenv.hostPlatform.system != "aarch64-linux") [
      waypipe-novideo # Forward Wayland apps from this host over SSH (useful for remote GUI debug on headless boxes)
    ]
    ++ [
      # Network & system diagnostics (fleet-wide debug floor)
      bind.dnsutils # dig, nslookup — resolved/NetBird/hosts-file DNS issues will come up
      mtr # traceroute + ping merged; debug NetBird mesh / container-bridge reachability
      lsof # "what's using port/file/LV?" — recurring need (LUKS unmount, port conflicts)
      iotop # disk I/O perpetrator finder (Frigate / paperless / syncthing)
      tcpdump # packet capture — last-resort network debugging
      lnav # TUI log navigator; much better than `journalctl | less` for spelunking
    ];

  environment.sessionVariables = {
    FLAKE = "${config.my.developDir}/nix-config";
    NH_FLAKE = "${config.my.developDir}/nix-config"; # nh 4.2+ support
  };

}
