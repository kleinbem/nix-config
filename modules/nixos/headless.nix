# headless.nix — Shared base module for all headless/remote nodes.
# Imports options.nix and provides a minimal NixOS config suitable for
# routers, edge devices, and headless servers (no desktop, Cockpit, etc).
{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
let
  keys = import ./keys.nix;
in
{
  imports = [
    ./options.nix
    inputs.sops-nix.nixosModules.sops
    ./services/tang.nix
  ];

  # Overlays (same as common.nix but without NUR/desktop-specific overlays)
  nixpkgs = {
    overlays = [
      inputs.nix-packages.overlays.default
      (_self: super: {
        stable = import inputs.nixpkgs-stable {
          inherit (super.stdenv.hostPlatform) system;
          config.allowUnfree = true;
        };
      })
    ];

    # ─── Nix settings ───────────────────────────────────────────
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
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
        "https://cache.kleinbem.dev/system"
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "system:EVrT+UgMV5xzRZSNKPEFflQwGc5qqgMro6PA5lzD05U="
        "cache.nixos.org-1:Ik/ZBziETSRre3nCpv7l4WwhDD5OhoOx9LG/mIJV6Hg="
        keys.cachix.nix-community
      ];
      builders-use-substitutes = true;
      trusted-users = [
        "@wheel"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # ─── Locale ─────────────────────────────────────────────────
  time.timeZone = "Europe/Dublin";
  i18n.defaultLocale = "en_IE.UTF-8";

  services = {
    # ─── mDNS (mDNS is essential for .local resolution) ────────
    avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };

    # ─── SSH (headless nodes need solid SSH) ────────────────────
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = lib.mkDefault "prohibit-password";
        PasswordAuthentication = false;
      };
    };

    # ─── Journal ────────────────────────────────────────────────
    journald.extraConfig = ''
      SystemMaxUse=256M
      MaxRetentionSec=1month
    '';
  };

  # ─── Minimal Packages ──────────────────────────────────────
  environment.systemPackages = with pkgs; [
    git
    curl
    btop
    jq
    ripgrep
    fd
  ];

  # ─── Swap ───────────────────────────────────────────────────
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # ─── User ───────────────────────────────────────────────────
  users.users.${config.my.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # TODO: Add your SSH public key here
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # ─── Silent Boot ────────────────────────────────────────────
  boot.kernelParams = [
    "quiet"
    "loglevel=3"
    "systemd.show_status=auto"
    "rd.udev.log_level=3"
  ];
}
