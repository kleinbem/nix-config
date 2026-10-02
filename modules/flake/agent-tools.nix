{
  perSystem =
    { pkgs, ... }:
    {
      # Pinned interpreter for scripts/sync-agent-context.sh's generators, so
      # `just dev::sync-agent` never depends on whichever python3 happens to
      # be first on the caller's PATH (devshell, home profile, leaked app
      # deps...). legacyPackages, not packages: `packages` is forced by
      # images.nix's container-factory eval, which would make this slow.
      legacyPackages.agent-python = pkgs.python3.withPackages (p: [ p.pyyaml ]);
    };
}
