# Shared pull-deploy profile for 24/7 hosts: autoUpgrade plus the ntfy
# fast-path (inert until the host declares the ntfy_deploy_topic secret).
# mkDefault so a host on my.deploy.comin can turn autoUpgrade off.
{ lib, ... }:
{
  my.deploy.autoUpgrade = {
    enable = lib.mkDefault true;
    requireCache = lib.mkDefault true;
    ntfy.enable = lib.mkDefault true;
  };
}
