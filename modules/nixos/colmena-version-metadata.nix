# Works around nix-community/colmena#162 (open since 2023): `meta.nixpkgs =
# import inputs.nixpkgs { ... };` in modules/flake/colmena.nix evaluates
# nixpkgs as a plain attrset, discarding the flake input's own
# rev/lastModified/shortRev metadata that system.nixos.versionSuffix's
# default computation needs — every colmena-evaluated host falls back to the
# generic "pre-git" label instead of "<date>.<shortrev>", a DIFFERENT label
# than a plain `nix build`/`nixos-rebuild` produces for the identical config
# (CI, `dev::apply`, `nix eval`). Since the label is part of the derivation,
# colmena-built closures can never hash-match what CI already built and
# pushed to Attic, silently forcing a full local rebuild on every deploy
# (QEMU-emulated for aarch64 targets: core-pi, hass-pi).
#
# Fix: recompute the same fields directly from `inputs.nixpkgs`/`self` (both
# already threaded through as specialArgs by modules/flake/colmena.nix's
# meta.specialArgs). Formula mirrors nixpkgs' own
# nixos/modules/misc/version.nix computation, so this is a no-op for the
# already-correct plain-eval path and only changes anything under colmena's
# metadata-stripping meta.nixpkgs.
#
# Only usable now that colmena runs in direct-flake-evaluation mode
# (github:nix-community/colmena main, see flake.nix's colmena input and
# colmena.nix's colmenaHive output) — the old builtins.getFlake + temp-copy
# bootstrap broke outright on any edit to colmena.nix when this was first
# attempted against the packaged v0.4.0.
{
  lib,
  inputs,
  self,
  ...
}:
{
  system = {
    nixos = {
      versionSuffix = ".${
        lib.substring 0 8 (inputs.nixpkgs.lastModifiedDate or inputs.nixpkgs.lastModified or "19700101")
      }.${inputs.nixpkgs.shortRev or "dirty"}";
      revision = lib.mkIf (inputs.nixpkgs ? rev) inputs.nixpkgs.rev;
    };
    configurationRevision = lib.mkIf (self ? rev) self.rev;
  };
}
