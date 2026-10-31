{
  inputs,
  config,
  lib,
  myInventory,
  secretFile,
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

  # Fleet-wide sops defaults — every host used to repeat these 3 lines
  # verbatim in its own secrets.nix; hoisted here 2026-09-11. mkDefault so a
  # host can still override (none currently need to).
  sops = {
    defaultSopsFile = lib.mkDefault (secretFile "nix/shared.yaml");
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

      # reuse: nixos-unstable's python builder now hands attrs over as
      # structured attrs, but sphinxHook still expands `$sphinxBuilders` as a
      # string, so only the first builder (html) runs and the `man` output is
      # never produced ("failed to produce output path for output 'man'";
      # khal hits the same, NixOS/nixpkgs#576161). amberol needs reuse at
      # build time, so every x86 desktop toplevel (mac-mini in CI) fails and
      # promote-production never publishes a container manifest. The real
      # fix is NixOS/nixpkgs#573479, merged to staging 2026-10-13 — drop
      # this once it reaches nixos-unstable. Until then skip the man build.
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
            # Hydra never gets past the compile error, so nothing upstream has
            # run this test suite on aarch64 yet. One test fails on the native
            # GH arm runner: test-tls-hello-parser-failure asserts the client
            # socket closes *with* an error after the server rejects 1 MiB of
            # garbage, which depends on RST-vs-FIN timing in the network stack
            # (build-all run 37293702282: `false !== true` at :64). Skipped the
            # same way nixpkgs skips its other environment-dependent TLS tests.
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

          # pyopenjtalk-plus 0.4.1-post9's test suite expects the exception
          # text of Cython < 3.3 ("must be str"); nixos-unstable 09063bd
          # ships Cython 3.3.0 ("Expected str, got int"), so one test fails
          # on every platform (hydra builds 349753099/349753109) and with it
          # piper-tts → wyoming-piper → the hass-pi toplevel. Upstream fixed
          # the test in tsukumijima/pyopenjtalk-plus@90b644f and
          # NixOS/nixpkgs#576063 backports it. Self-retiring: a no-op once
          # the pinned package already carries a cython patch — delete this
          # block once #576063 reaches nixos-unstable.
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
