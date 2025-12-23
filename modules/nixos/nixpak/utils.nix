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
      configDir ? name,
      binPath ? "bin/${name}",
      extraPerms ? { },
      extraPackages ? [ ],
      presets ? [ ],
    }:
    let
      # If extra packages are requested, create a combined environment
      envPackage =
        if extraPackages == [ ] then
          package
        else
          pkgs.symlinkJoin {
            name = "${name}-env";
            paths = [ package ] ++ extraPackages;
          };

      # --- PERMISSION PRESETS ---
      availablePresets = {
        network = {
          bubblewrap.network = true;
        };
        wayland =
          { sloth, ... }:
          {
            bubblewrap.env = {
              NIXOS_OZONE_WL = "1";
              XDG_SESSION_TYPE = "wayland";
              WAYLAND_DISPLAY = sloth.env "WAYLAND_DISPLAY";
            };
          };
        gpu = {
          bubblewrap.bind = {
            dev = [ "/dev/dri" ];
            ro = [
              "/run/opengl-driver"
              "/sys/class/drm"
            ];
          };
        };
        audio =
          { sloth, ... }:
          {
            bubblewrap.bind.rw = [
              (sloth.concat' sloth.runtimeDir "/pipewire-0")
            ];
          };
        usb = {
          bubblewrap.bind = {
            ro = [
              "/sys/bus/usb"
              "/sys/dev"
              "/run/udev"
            ];
          };
        };
      };

      # Select requested presets
      activePresets = map (p: availablePresets.${p}) presets;

      sandbox = mkNixPak {
        config =
          { ... }:
          {
            imports = [
              (
                { sloth, ... }:
                {
                  app.package = envPackage;
                  app.binPath = binPath;
                  flatpak.appId = "com.sandboxed.${name}";

                  # Base binds that everyone needs
                  bubblewrap.bind.ro = [
                    "/etc/fonts"
                    "/etc/ssl/certs"
                    "/etc/profiles/per-user"
                    "/run/dbus"
                    (sloth.concat' sloth.homeDir "/.icons")
                  ];

                  bubblewrap.bind.rw = [
                    (sloth.env "XDG_RUNTIME_DIR")
                    "/tmp"
                    (sloth.concat' sloth.homeDir "/.config/${configDir}")
                  ];
                }
              )
              extraPerms
            ]
            ++ activePresets;
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
