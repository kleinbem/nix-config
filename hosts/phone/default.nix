{
  pkgs,
  ...
}:

{
  # ─── Nix-on-Droid System Configuration ────────────────────────
  # This corresponds to the nix-on-droid.nix file

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
    btop
    openssh
    rsync
    curl
    wget
    tree
    ncurses

    # Dev Tools from your meta-repo (Temporarily disabled for bootstrapping)
    # inputs.nix-devshells.packages.${pkgs.system}.default
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
          ../../users/martin/home-phone.nix
        ];

        # Override home.stateVersion for Nix-on-Droid if needed
        home.stateVersion = "24.05";

        # Disable desktop-specific parts of your home-manager config if they exist
        # (assuming your home.nix has options to toggle them)
      };
  };

  # ─── Nix Configuration ───────────────────────────────────────
  # Pin Nix to 2.24 to work around proot-termux TCGETS2 bug (nix-on-droid#495)
  # Remove this once proot-termux PR#529 is merged into release-24.05
  nix.package = pkgs.nixVersions.nix_2_24;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';
}
