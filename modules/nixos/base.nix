{
  inputs,
  config,
  lib,
  myInventory,
  secretFile,
  ...
}:
# Foundational modules every deployed NixOS host pulls in, through every
# entry-point bundle (see docs/MODULE-ORGANIZATION.md). Add fleet-wide
# concerns here once. Not imported by phone (nix-on-droid), container-factory
# (never boots) or orin-nano-bootstrap (installer image).
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
    # Its successor: comin polls the production branch (my.deploy.comin).
    # Option only — hosts opt in, mutually exclusive with autoUpgrade.
    ./comin.nix

    # Core services / system-wide concerns
    ./networking.nix
    ./network-routing.nix # inter-host routes generated from inventory
    ./attic-pull.nix # authenticated + NetBird-routed reads of the private Attic cache (gated on attic_pull_token)
    ./pki.nix
    ./virtualisation.nix
    ./zero-trust.nix
    ./forward-auth-guard.nix # auth = true inventory nodes reachable only via Caddy (nftables hosts)
    ./services/timesync.nix
    ./services/mesh-llm.nix # my.services.meshLlm — a MeshLLM node in the fleet mesh; per-host opt-in
    ./machine-id.nix # my.machineId — stable machine-id on the tmpfs root (kernel cmdline pin)
    ./backup.nix # my.backup — fleet destinations/keys for nix-presets' backup-engine (off until a host enables it)
    ./heartbeat.nix # my.heartbeat — external dead-man's switch (healthchecks.io); per-host opt-in
    ./claude-code.nix # my.claudeCode — Claude Code managed settings (permission + auto-mode policy); per-host opt-in
    ./host-secrets.nix # my.hostSecrets — host-local plaintext keys (initrd SSH, LUKS key files), never in the store
  ];

  # Fleet-wide sops defaults; mkDefault so a host can override.
  sops = {
    defaultSopsFile = lib.mkDefault (secretFile "nix/shared.yaml");
    defaultSopsFormat = lib.mkDefault "yaml";
    # CI builds with a dummy secrets tree, so the build-time key check would
    # abort. Activation still decrypts the real files.
    validateSopsFiles = lib.mkDefault false;
  };

  # Custom-packages overlay — used by every host. Workstation-only overlays
  # (NUR, vscode-extensions, nix-topology, nixpkgs-master) stay in
  # workstation.nix; the `stable` overlay below stays universal so any host
  # can do `pkgs.stable.X` from headless and workstation modules alike.
  nixpkgs.overlays = [
    inputs.nix-packages.overlays.default
    # Packages held back from nixos-unstable while broken there; ours too.
    (inputs.nix-holds-fleet.lib.mkOverlay { extraOverlays = [ inputs.nix-packages.overlays.default ]; })
    (_final: prev: {
      stable = import inputs.nixpkgs-stable {
        inherit (prev.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };

      # -----------------------------------------------------------------------
      # Fixes for nixos-unstable regressions that need a change to the package.
      # A package that only needs another nixpkgs (stable, or the last commit
      # where it worked) goes to kleinbem/nix-holds-fleet instead.
      # -----------------------------------------------------------------------

      # reuse: sphinxHook expands `$sphinxBuilders` as a string under
      # structured attrs, so only html runs and the `man` output is never
      # produced; amberol needs reuse to build. Drop once NixOS/nixpkgs#573479
      # reaches nixos-unstable.
      reuse = prev.python3Packages.toPythonApplication (
        prev.python3Packages.reuse.overrideAttrs (old: {
          # keep out/doc/dist (the python builder adds dist itself)
          outputs = prev.lib.remove "man" old.outputs;
          sphinxBuilders = [ "html" ];
        })
      );

      # flashrom 1.8.0's cmocka test suite fails on aarch64
      # (`write_chip_bad_status_test`), which breaks raspberrypi-eeprom →
      # rpi-eeprom-update.service → the whole core-pi/hass-pi toplevel.
      # Upstream-flaky, not our bug; skip the check until nixpkgs fixes it.
      flashrom = prev.flashrom.overrideAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
      });

      # nodejs 26.10.0 fails on aarch64 under GCC 16: V8's memcopy.h uses
      # CHAR_BIT without <climits> (NixOS/nixpkgs#568974). aarch64 only so
      # x86_64 keeps Hydra's cache. Self-retiring once the version moves or
      # upstream adds <climits>; delete it then.
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
            # test-tls-hello-parser-failure depends on RST-vs-FIN timing and
            # fails on the GH arm runner; skipped like nixpkgs' other
            # environment-dependent TLS tests.
            checkFlags = map (
              f: if lib.hasPrefix "CI_SKIP_TESTS=" f then f + ",test-tls-hello-parser-failure" else f
            ) old.checkFlags;
          });

      # Fix pygount build failure in nix-hardware (strict chardet bound)
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (_python-final: python-prev: {
          pygount = python-prev.pygount.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ python-prev.pythonRelaxDepsHook ];
            pythonRelaxDeps = [ "chardet" ];
          });

          # pyopenjtalk-plus tests expect Cython < 3.3's error text, which breaks
          # piper-tts and the hass-pi toplevel. Upstream fix backported in
          # NixOS/nixpkgs#576063; no-op once a cython patch is present, delete
          # once it reaches nixos-unstable.
          pyopenjtalk-plus =
            if
              lib.any (p: lib.hasInfix "cython" (p.name or "")) (python-prev.pyopenjtalk-plus.patches or [ ])
            then
              python-prev.pyopenjtalk-plus
            else
              python-prev.pyopenjtalk-plus.overrideAttrs (old: {
                patches = (old.patches or [ ]) ++ [
                  (prev.fetchpatch {
                    name = "fix-cython-3.3.0.patch";
                    url = "https://github.com/tsukumijima/pyopenjtalk-plus/commit/90b644f9e9d397882e6eafe4dcd1843a4fde6a63.patch";
                    includes = [ "tests/test_frontend.py" ];
                    hash = "sha256-Jb7T/bRUHxqwBLwV6xYC/teaFHm5GmqJxA7sCX+oiNI=";
                  })
                ];
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
      inherit inputs myInventory secretFile;
      inherit (config) my;
    };
    backupFileExtension = "backup";
  };
}
