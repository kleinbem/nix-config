{
  pkgs,
  inputs,
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

    # Dev Tools from your meta-repo
    inputs.nix-devshells.packages.${pkgs.system}.default
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
          # You might need to make home.nix slightly more generic if it has X11/Wayland stuff
          # but for now let's try importing your main user config
          ../../users/martin/home.nix
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
}
