{
  description = "AI-Augmented NixOS with COSMIC and Firejail";

  inputs = {
    # --- Core ---
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.ghostty.follows = "ghostty";
    };

    ghostty = {
      url = "github:mitchellh/ghostty";
    };

    impermanence.url = "github:nix-community/impermanence";

    # Secret Management
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Private Secrets (GitHub Repo)
    nix-secrets = {
      url = "github:kleinbem/nix-secrets";
      flake = false;
    };

    # Modules & Configurations (Pulled from local submodules for speed)
    nix-hardware = {
      url = "github:kleinbem/nix-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.jetpack-nixos.follows = "jetpack-nixos";
    };
    nix-devshells = {
      url = "github:kleinbem/nix-devshells";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-presets = {
      url = "github:kleinbem/nix-presets";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-packages = {
      url = "github:kleinbem/nix-packages";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-templates = {
      url = "github:kleinbem/nix-templates";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix User Repository
    nur = {
      url = "github:nix-community/NUR";
    };

    # Image Generation
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jetpack-nixos = {
      url = "github:anduril/jetpack-nixos";
      # intentionally NOT following nixpkgs — anduril's cache is built with jetpack's pinned nixpkgs
    };

    # cosmic flake removed — using nixpkgs COSMIC instead (more reliable, pre-built by Hydra)

    # Multi-host Deployment
    # colmena flake removed — using nixpkgs instead

    nix-topology = {
      url = "github:oddlama/nix-topology";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-mineral = {
      url = "github:cynicsketch/nix-mineral";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      # NOTE: Do NOT follow nixpkgs here. nix-on-droid needs its own pinned
      # nixpkgs with an older glibc to avoid the TCGETS2 proot-termux bug.
      # See: https://github.com/nix-community/nix-on-droid/issues/495
      inputs.home-manager.follows = "home-manager";
    };

    claude-for-linux = {
      url = "github:heytcass/claude-for-linux";
    };

    claude-cowork-nix = {
      url = "github:Reginleif88/claude-cowork-nix";
    };

  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./modules/flake/images.nix
        inputs.nix-topology.flakeModule
        ./modules/flake/checks.nix
        ./modules/flake/hosts.nix
        ./modules/flake/colmena.nix
        ./modules/flake/nix-on-droid.nix
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
}
