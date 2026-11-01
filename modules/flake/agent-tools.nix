{
  perSystem =
    { pkgs, ... }:
    {
      # Pinned python for scripts/sync-agent-context.sh, independent of PATH.
      # legacyPackages, not packages: images.nix's container-factory eval
      # forces `packages`, which would make this slow.
      legacyPackages.agent-python = pkgs.python3.withPackages (p: [ p.pyyaml ]);
    };
}
