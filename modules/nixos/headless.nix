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

{
  imports = [
    ./options.nix
    inputs.sops-nix.nixosModules.sops
  ];

  # Overlays (same as common.nix but without NUR/desktop-specific overlays)
  nixpkgs.overlays = [
    inputs.nix-packages.overlays.default
    (_self: super: {
      stable = import inputs.nixpkgs-stable {
        inherit (super.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
    })
  ];

  # ─── Nix settings ───────────────────────────────────────────
  nixpkgs.config.allowUnfree = true;
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
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:Ik/ZBziETSRre3nCpv7l4WwhDD5OhoOx9LG/mIJV6Hg="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
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

  # ─── SSH (headless nodes need solid SSH) ────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkDefault "prohibit-password";
      PasswordAuthentication = false;
    };
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

  # ─── Journal ────────────────────────────────────────────────
  services.journald.extraConfig = ''
    SystemMaxUse=256M
    MaxRetentionSec=1month
  '';

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
}
