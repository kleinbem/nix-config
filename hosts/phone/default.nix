{
  pkgs,
  inputs,
  self,
  ...
}:

{
  # ─── Nix-on-Droid System Configuration ────────────────────────
  # This corresponds to the nix-on-droid.nix file

  imports = [
    "${self}/modules/nix-on-droid/dashboard.nix"
  ];

  system.stateVersion = "24.05";

  # ─── Terminal & Shell ─────────────────────────────────────────
  terminal.font = "${pkgs.fira-code}/share/fonts/opentype/FiraCode-Regular.otf";

  user.shell = "${pkgs.zsh}/bin/zsh";

  # ─── Environment ──────────────────────────────────────────────
  environment.packages = with pkgs; [
    # Core Utilities
    vim
    git
    htop
    # olivetin
    btop
    openssh
    rsync
    curl
    wget
    tree
    ncurses

    # Dev Tools from your meta-repo (Temporarily disabled for bootstrapping)
    # inputs.nix-devshells.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # ─── Home Manager Integration ────────────────────────────────
  # We can share your existing Home Manager config!
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    config =
      { ... }:
      {
        imports = [
          # Use the slimmed-down phone config to avoid desktop circular dependencies
          "${self}/users/martin/home-phone.nix"
        ];

        # Override home.stateVersion for Nix-on-Droid if needed
        home.stateVersion = "24.05";

        # Disable desktop-specific parts of your home-manager config if they exist
        # (assuming your home.nix has options to toggle them)
      };
  };

  # ─── Nix Configuration ───────────────────────────────────────

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Pin the flake registry for faster offline lookups
  nix.registry = {
    nix-config.flake = self;
    nix-presets.flake = inputs.nix-presets;
    nix-devshells.flake = inputs.nix-devshells;
  };

  # ─── SSH Configuration (Managed via Home Manager) ─────────────
  # services.openssh.enable = true;
  # users.users.nix-on-droid.openssh.authorizedKeys.keys = [
  #   "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFLSRkt7uoF1c2iWpwt7mJi2krEtmpdUD4wLUm0XTn5JbGIBce+avhSqY02YRe3dpRVqo7KGE8upe11xI8IcEjk= PIV AUTH pubkey"
  # ];
}
