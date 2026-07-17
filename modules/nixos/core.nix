{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:
let
  keys = import ./keys.nix;
in
{
  # Wraps nix-index/nix-locate with the prebuilt weekly database, so the
  # command-not-found hook works without ever running `nix-index` locally.
  imports = [ inputs.nix-index-database.nixosModules.default ];

  # ==========================================
  # NIX SETTINGS & CORE
  # ==========================================

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
      ];
      auto-optimise-store = true;
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
        "https://cuda-maintainers.cachix.org"
        "https://anduril.cachix.org"
        "https://cache.kleinbem.dev/system"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:Ik/ZBziETSRre3nCpv7l4WwhDD5OhoOx9LG/mIJV6Hg="
        keys.cachix.nix-community
        keys.cachix.devenv
        keys.cachix.cuda-maintainers
        keys.cachix.anduril
        "system:dCe+aNk1+Dwf3IG6OVBKcf5h0oL0hkRVqYiLN7iOJhU="
      ];
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

  # ==========================================
  # PKI CERTIFICATES (Fleet Trust Chain)
  # ==========================================
  # Root CA of the caddy container that terminates TLS for cache.kleinbem.dev
  # (on core-pi). SINGLE SOURCE OF TRUTH: the same file CI trusts
  # (.github/actions/nix-fleet-setup). If the caddy container is ever recreated
  # or moved, Caddy mints a NEW local CA — refresh this file from
  # /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt on the
  # host that runs it, or the whole fleet fails cert verification against the
  # cache (2026-07-07 outage).
  security.pki.certificateFiles = [ ../../pki/caddy-root.crt ];

  services = {
    xserver.xkb.layout = "gb";

    # Prevent /var/log/journal from growing indefinitely. 1G rotated out in
    # under a day on the workstation (runners + fluent-bit churn), leaving
    # incidents un-diagnosable; headless.nix overrides tighter for RPi nodes.
    journald.extraConfig = "SystemMaxUse=4G";

    # = hardware monitoring =
    smartd.enable = true;
    fwupd.enable = true;

    # Mobile Device Support
    gvfs.enable = true; # MTP/PTP support for file transfer

    # Mitigate kernel panics under extreme memory pressure (AI workloads)
    earlyoom = {
      enable = true;
      # m=5: kill at 5% free memory, s=10: kill at 10% free swap
      # --prefer: browser sub-processes (safe to restart)
      # --ignore: GUI and shell (keep system interactive)
      extraArgs = [
        "-m"
        "5"
        "-s"
        "10"
        "--prefer"
        "^(firefox|chrome|chromium)$"
        "--ignore"
        "^(gnome-shell|Xwayland|bash|zsh)$"
      ];
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

  environment.systemPackages = with pkgs; [
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

    android-tools # ADB & Fastboot
    lm_sensors # Hardware heat sensors
    waypipe # Forward Wayland apps from this host over SSH (useful for remote GUI debug on headless boxes)

    # Network & system diagnostics (fleet-wide debug floor)
    bind.dnsutils # dig, nslookup — resolved/NetBird/hosts-file DNS issues will come up
    mtr # traceroute + ping merged; debug NetBird mesh / container-bridge reachability
    lsof # "what's using port/file/LV?" — recurring need (LUKS unmount, port conflicts)
    iotop # disk I/O perpetrator finder (Frigate / paperless / syncthing)
    tcpdump # packet capture — last-resort network debugging
    lnav # TUI log navigator; much better than `journalctl | less` for spelunking
  ];

  environment.sessionVariables = {
    FLAKE = "${config.my.developDir}/nix/nix-config";
    NH_FLAKE = "${config.my.developDir}/nix-config"; # nh 4.2+ support
  };

}
