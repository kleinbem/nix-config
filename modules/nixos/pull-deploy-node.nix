# Shared profile for 24/7 hosts that substitute from Attic: pull-based
# auto-upgrade plus the ntfy fast-path. Import it rather than repeating the
# block, so hosts only drift through a deliberate override.
#
# The ntfy listener stays inert until the host declares the ntfy_deploy_topic
# sops secret. mkDefault so a host on my.deploy.comin can turn autoUpgrade off.
{ lib, ... }:
{
  my.deploy.autoUpgrade = {
    enable = lib.mkDefault true;
    requireCache = lib.mkDefault true;
    ntfy.enable = lib.mkDefault true;
  };
}
