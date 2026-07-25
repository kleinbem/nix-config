# aarch64 variant of the container factory: the full catalogue minus
# containers that only make sense on x86_64. Everything else stays enabled so
# any container can be moved to an ARM host and picked up from the same
# CI-published manifest (standalone-everywhere, ADR 002 in the meta repo).
{ ... }:
{
  imports = [ ./default.nix ];

  my.containers = { };
}
