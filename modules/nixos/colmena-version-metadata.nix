# Works around nix-community/colmena#162: colmena's meta.nixpkgs drops the
# flake's rev metadata, so versionSuffix falls back to "pre-git" and
# colmena closures never match what CI pushed to Attic. Recompute the fields
# the way nixos/modules/misc/version.nix does; a no-op outside colmena.
# Needs colmena's direct-flake-evaluation mode (colmena main, not v0.4.0).
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
