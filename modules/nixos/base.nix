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
  ];

  # Fleet-wide sops defaults — every host used to repeat these 3 lines
  # verbatim in its own secrets.nix; hoisted here 2026-09-11. mkDefault so a
  # host can still override (none currently need to).
  sops = {
    defaultSopsFile = lib.mkDefault "${inputs.nix-secrets}/nix/shared.yaml";
    defaultSopsFormat = lib.mkDefault "yaml";
    # Don't fail the *build* validating secret presence against the sops
    # file. CI builds every host's toplevel with an empty dummy
    # nix/shared.yaml (--override-input nix-secrets /tmp/dummy-secrets),
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
