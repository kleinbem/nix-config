{
  inputs,
  config,
  lib,
  myInventory,
  ...
}:
# Foundational modules every deployed NixOS host should pull in by default.
#
# Imported by `modules/nixos/default.nix`, `modules/nixos/rpi5-node.nix`, and
# directly by `hosts/{mac-mini,nasbook,orin-nano}/default.nix` (Pattern B
# devices — see docs/MODULE-ORGANIZATION.md), plus the router LXC guests —
# every entry-point bundle the fleet uses. To add a new fleet-wide
# foundational concern, add it here once instead of touching every entry
# point.
#
# Excluded by design:
#   - phone (nix-on-droid, different module system)
#   - container-factory (build-only, never boots)
#   - orin-nano-bootstrap (installer/recovery image)
{
  imports = [
    # my.* schema (declares every option the rest of the fleet sets).
    ./options.nix

    # Sops-encrypted secrets infrastructure (host needs it to read its own
    # secrets; the actual secret definitions live per-host or in services).
    inputs.sops-nix.nixosModules.sops

    # Home-manager NixOS module — hosts with user-environment configs (orin,
    # nixos-nvme, nasbook) opt in by setting `home-manager.users.<name>`.
    # Hosts without users (routers) leave it unconfigured; the module is
    # cheap when unused.
    inputs.home-manager.nixosModules.home-manager

    # System-wide foundation (Nix settings, locale, kernel-tuning baselines,
    # CLI tool floor, fleet trust chain — see core.nix). Self-guards the
    # optional sops token, so it's safe to import everywhere.
    ./core.nix

    # Pull-based fleet auto-upgrade option (my.deploy.autoUpgrade).
    # Option only — default disabled. Hosts opt in per-host.
    ./auto-upgrade.nix

    # Core services / system-wide concerns
    ./networking.nix
    ./network-routing.nix # inter-host routes generated from inventory
    ./attic-pull.nix # authenticated + NetBird-routed reads of the private Attic cache (gated on attic_pull_token)
    ./pki.nix
    ./virtualisation.nix
    ./zero-trust.nix
    ./services/timesync.nix
    ./machine-id.nix # my.machineId — stable machine-id on the tmpfs root (kernel cmdline pin)
    ./backup.nix # my.backup — fleet destinations/keys for nix-presets' backup-engine (off until a host enables it)
    ./heartbeat.nix # my.heartbeat — external dead-man's switch (healthchecks.io); per-host opt-in
  ];

  # Fleet-wide sops defaults — every host used to repeat these 3 lines
  # verbatim in its own secrets.nix; hoisted here 2026-09-11. mkDefault so a
  # host can still override (none currently need to).
  sops = {
    defaultSopsFile = lib.mkDefault "${inputs.kleinbem-secrets}/nix/shared.yaml";
    defaultSopsFormat = lib.mkDefault "yaml";
    # Don't fail the *build* validating secret presence against the sops
    # file. CI builds every host's toplevel with an empty dummy
    # nix/shared.yaml (--override-input kleinbem-secrets /tmp/dummy-secrets),
    # so sops-install-secrets' build-time manifest check would otherwise
    # abort on "key '<foo>' cannot be found" — the documented sops-nix CI
    # workaround. Real decryption at activation is unaffected (it uses the
    # real shared/per-host files on the host).
    validateSopsFiles = lib.mkDefault false;
  };

  # Custom-packages overlay — used by every host. Workstation-only overlays
  # (NUR, vscode-extensions, nix-topology, nixpkgs-master) stay in
  # workstation.nix; the `stable` overlay below stays universal so any host
  # can do `pkgs.stable.X` from headless and workstation modules alike.
  nixpkgs.overlays = [
    inputs.nix-packages.overlays.default
    (_final: prev: {
      stable = import inputs.nixpkgs-stable {
        inherit (prev.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };

      # flashrom 1.8.0's cmocka test suite fails on aarch64
      # (`write_chip_bad_status_test`), which breaks raspberrypi-eeprom →
      # rpi-eeprom-update.service → the whole core-pi/hass-pi toplevel.
      # Upstream-flaky, not our bug; skip the check until nixpkgs fixes it.
      flashrom = prev.flashrom.overrideAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
      });

      # zotero 10.0.2 fails to build at nixpkgs b4fd65b ("AboutTranslations
      # … not found in modules/ActorManagerParent.sys.mjs -- aborting"; via
      # firejail-wrapped-binaries it broke the workstation toplevels and with
      # them every promote). Same 10.0.2, from the pinned last-good rev —
      # see the nixpkgs-zotero input in flake.nix for when to delete this.
      inherit
        (import inputs.nixpkgs-zotero {
          inherit (prev.stdenv.hostPlatform) system;
          config.allowUnfree = true;
        })
        zotero
        ;

      # herdr 0.9.1 fails to link on Linux with nixpkgs b4fd65b's toolchain
      # (ld.bfd: ".eh_frame_hdr refers to overlapping FDEs") — the bundled
      # libghostty-vt bakes in its own compiler_rt/ubsan_rt. Broke every
      # herdr host's toplevel (mac-mini first), blocking all promotes
      # 2026-10-01. Backport of upstream NixOS/nixpkgs#568618 (merged
      # 2026-09-30, not yet in nixos-unstable). Self-retiring: skipped as
      # soon as the pinned herdr already carries that postPatch — delete
      # this block once it does.
      herdr =
        if lib.hasInfix "bundle_compiler_rt" (prev.herdr.postPatch or "") then
          prev.herdr
        else
          prev.herdr.overrideAttrs (old: {
            postPatch =
              (old.postPatch or "")
              + lib.optionalString prev.stdenv.hostPlatform.isLinux ''
                substituteInPlace vendor/libghostty-vt/src/build/GhosttyLibVt.zig \
                  --replace-fail 'lib.bundle_compiler_rt = true;' 'lib.bundle_compiler_rt = false;' \
                  --replace-fail 'lib.bundle_ubsan_rt = true;' 'lib.bundle_ubsan_rt = false;'
              '';
          });

      # usbguard 1.1.4 fails to compile against newer abseil-cpp/protobuf
      # under -std=c++17 ("error: 'upper_bound' has not been declared in
      # 'using absl::btree_map...'"). Backport of upstream NixOS/nixpkgs#568672
      # (commit 804af16, merged 2026-09-30, not yet in pinned nixos-unstable).
      # Self-retiring: skipped as soon as the pinned usbguard already carries -std=c++20.
      usbguard =
        if lib.hasInfix "-std=c++20" (prev.usbguard.postPatch or "") then
          prev.usbguard
        else
          prev.usbguard.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace configure.ac \
                --replace-fail "-std=c++17" "-std=c++20"
            '';
          });

      # nodejs 26.10.0 fails to compile on aarch64-linux under GCC 16: V8's
      # NEON-only path in deps/v8/src/base/memcopy.h uses CHAR_BIT without
      # including <climits> (NixOS/nixpkgs#568974, no fix PR yet). Breaks
      # every aarch64 host pulling nodejs_latest — orin-nano via its CUDA
      # llama-cpp (webui build). aarch64-linux only so x86_64 keeps Hydra's
      # cached build. Self-retiring: skipped once nodejs-slim_26 moves past
      # 26.10.0 or upstream's postPatch already adds <climits> — delete this
      # block then.
      nodejs-slim_26 =
        if
          !prev.stdenv.hostPlatform.isAarch64
          || prev.nodejs-slim_26.version != "26.10.0"
          || lib.hasInfix "climits" (prev.nodejs-slim_26.postPatch or "")
        then
          prev.nodejs-slim_26
        else
          prev.nodejs-slim_26.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace deps/v8/src/base/memcopy.h \
                --replace-fail '#include <stdlib.h>' '#include <climits>
              #include <stdlib.h>'
            '';
          });

      # Fix pygount build failure in nix-hardware (strict chardet bound)
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (_python-final: python-prev: {
          pygount = python-prev.pygount.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ python-prev.pythonRelaxDepsHook ];
            pythonRelaxDeps = [ "chardet" ];
          });
        })
      ];
    })
  ];

  # Global home-manager settings (no-op on hosts that don't define users).
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs myInventory;
      inherit (config) my;
    };
    backupFileExtension = "backup";
  };
}
