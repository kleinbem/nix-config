{
  myInventory,
  lib,
  config,
  ...
}:
let
  cfg = config.modules.service-launchers;
  # Filter nodes that have metadata (which usually means they are human-facing services)
  services = lib.filterAttrs (_: node: node ? meta) myInventory.network.nodes;

  mkDesktopEntry = name: node: {
    name = node.meta.name or name;
    genericName = node.meta.category or "Service";
    comment = node.meta.description or "";
    exec = "xdg-open http://${node.ip}${
      if node ? externalPort then
        ":" + (builtins.toString node.externalPort)
      else if node ? port then
        ":" + (builtins.toString node.port)
      else
        ""
    }";
    icon = "web-browser"; # We could map icons from node.meta.icon if we had a mapping
    categories = [
      "Network"
      "WebBrowser"
    ];
    settings = {
      Keywords = "homelab;service;${node.meta.category or ""}";
    };
  };
in
{
  options.modules.service-launchers = {
    enable = lib.mkEnableOption "Desktop launchers for homelab services";
  };

  config = lib.mkIf cfg.enable {
    xdg.desktopEntries = lib.mapAttrs mkDesktopEntry services;
  };
}
