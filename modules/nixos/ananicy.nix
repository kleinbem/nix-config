{ pkgs, ... }:

let
  # ananicy-cpp 1.2.0 fails to build against current nixpkgs libc++: several
  # source files use std::memset/std::int32_t etc. without including
  # <cstring>/<cstdint> (relying on transitive includes that newer libc++
  # no longer provides). Prepend both headers to every .cpp file rather than
  # tracking down each individual missing include. Fix upstream via a patch
  # once released; drop this override then.
  ananicy-cpp-fixed = pkgs.ananicy-cpp.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      find src -name '*.cpp' -exec sed -i '1i #include <cstring>\n#include <cstdint>' {} +
    '';
  });
in
{
  # ==========================================
  # ANANICY-CPP — Auto-Nice Daemon
  # ==========================================
  # This daemon automatically prioritizes interactive applications (GNOME Shell
  # and Browsers) over background tasks (like Nix builds and AI containers).

  services.ananicy = {
    enable = true;
    package = ananicy-cpp-fixed;
    rulesProvider = ananicy-cpp-fixed;
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
        name = "firefox";
        type = "Web_Browser";
      }
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
