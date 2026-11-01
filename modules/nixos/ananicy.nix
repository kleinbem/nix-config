{ pkgs, ... }:

{
  # ananicy-cpp: interactive apps (GNOME Shell, browsers) get priority over
  # background work like Nix builds and AI containers.

  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-cpp;
    settings.apply_cgroups = false;
    extraRules = [
      # Prioritize the GNOME desktop environment
      {
        name = "gnome-shell";
        type = "Game";
      } # "Game" type gives high priority
      {
        name = "Xwayland";
        type = "Game";
      }

      # Prioritize Browsers for smooth scrolling during builds
      {
        name = "chrome";
        type = "Web_Browser";
      }
      {
        name = "chromium";
        type = "Web_Browser";
      }

      # Deprioritize Nix Builds and Containers
      {
        name = "nix-daemon";
        type = "Background";
      }
      {
        name = "nix";
        type = "Background";
      }
      {
        name = "podman";
        type = "Background";
      }
    ];
  };
}
