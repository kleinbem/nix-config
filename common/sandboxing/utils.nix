{ pkgs, nixpak }:

rec {
  mkNixPak = nixpak.lib.nixpak {
    inherit (pkgs) lib;
    inherit pkgs;
  };

  mkSandboxed =
    {
      package,
      name ? package.pname,
      binPath ? "bin/${name}",
      extraPerms ? { },
    }:
    let
      sandbox = mkNixPak {
        config =
          { ... }:
          {
            imports = [
              (
                { sloth, ... }:
                {
                  app.package = package;
                  app.binPath = binPath;
                  flatpak.appId = "com.sandboxed.${name}";

                  bubblewrap = {
                    network = true;
                    env = {
                      NIXOS_OZONE_WL = "1";
                      XDG_SESSION_TYPE = "wayland";
                      WAYLAND_DISPLAY = sloth.env "WAYLAND_DISPLAY";
                    };

                    # Grouped bindings to satisfy linter
                    bind = {
                      dev = [ "/dev/dri" ];

                      ro = [
                        # --- Basics ---
                        "/etc/fonts"
                        "/etc/ssl/certs"
                        "/etc/profiles/per-user"
                        "/run/dbus"
                        (sloth.concat' sloth.homeDir "/.icons")

                        # --- The "Nuclear" Graphics Fix for Intel ---
                        "/run/opengl-driver"
                        "/sys/class/drm"
                        "/sys/devices"
                        "/sys/dev" # <--- Critical for identifying devices
                        "/etc/udev" # <--- Sometimes needed for device lookup
                      ];

                      rw = [
                        (sloth.env "XDG_RUNTIME_DIR")
                        "/tmp"
                        (sloth.concat' sloth.homeDir "/.config/${name}")
                      ];
                    };
                  };
                }
              )
              extraPerms
            ];
          };
      };

      # Fixed W04: Assignment instead of inherit
      inherit (sandbox.config) script;

    in
    pkgs.runCommand "${name}-sandboxed" { } ''
      mkdir -p $out/bin
      ln -s ${script}/bin/${name} $out/bin/${name}

      if [ -d "${package}/share" ]; then
        mkdir -p $out/share
        if [ -d "${package}/share/icons" ]; then
          ln -s ${package}/share/icons $out/share/icons
        fi
        if [ -d "${package}/share/applications" ]; then
          cp -r ${package}/share/applications $out/share/applications
          chmod -R u+w $out/share/applications
          sed -i "s|^Exec=.*|Exec=$out/bin/${name} %u|" $out/share/applications/*.desktop
          sed -i "s|^Name=${
            package.meta.description or name
          }|Name=${name} (Secure)|" $out/share/applications/*.desktop
        fi
      fi
    '';
}
