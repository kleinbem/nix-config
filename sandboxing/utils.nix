# sandboxing/utils.nix
{ pkgs, nixpak }:

rec {
  # 1. Initialize the builder
  mkNixPak = nixpak.lib.nixpak {
    inherit (pkgs) lib;
    inherit pkgs;
  };

  # 2. Define the Reusable Function
  # It takes a package, a name, and a list of specific permissions (extraPerms)
  mkSandboxed = { package, name ? package.pname, binPath ? "bin/${name}", extraPerms ? {} }:
    mkNixPak {
      config = { sloth, ... }: {
        
        # --- App Basics ---
        app.package = package;
        app.binPath = binPath;
        flatpak.appId = "com.sandboxed.${name}"; # Helps Window Managers track it

        # --- The "Base" COSMIC/Wayland Sandbox ---
        bubblewrap = {
          network = true; # Default to true, override in extraPerms if needed
          
          # Force Wayland (Critical for COSMIC)
          env = {
            NIXOS_OZONE_WL = "1";
            WAYLAND_DISPLAY = "wayland-0";
            XDG_SESSION_TYPE = "wayland";
          };

          # Common Read-Only Paths (Fonts, SSL, Icons)
          bind.ro = [
            "/etc/fonts"
            "/etc/ssl/certs"
            "/etc/profiles/per-user" # Helps find themes
            (sloth.concat' sloth.homeDir "/.icons") 
          ];

          # Common Read-Write Paths (Wayland Sockets, Audio, Temp)
          bind.rw = [
            (sloth.env "XDG_RUNTIME_DIR")
            "/tmp"
            
            # Allow app to save its own config in ~/.config/app-name
            (sloth.concat' sloth.homeDir "/.config/${name}")
          ];
        };
      } 
      # 3. Merge app-specific permissions
      // extraPerms; 
    };
}