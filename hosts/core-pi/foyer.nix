# Foyer's /config.json (home.kleinbem.dev), generated from the inventory.
{
  lib,
  myInventory,
  # Gatus endpoints: a service probed there gets live health.
  gatusEndpoints,
}:
let
  inherit (myInventory) hosts;
  inherit (myInventory.network) nodes;

  # "10.85.48.0/24" -> "10.85.48."
  subnetPrefix = subnet: lib.removeSuffix "0/24" subnet;

  hostOf =
    node:
    node.host or (lib.findFirst (
      name:
      let
        h = hosts.${name};
      in
      (h ? containerSubnet && lib.hasPrefix (subnetPrefix h.containerSubnet) node.ip)
      || (h.physicalIp or h.ip or null) == node.ip
    ) "fleet" (lib.attrNames hosts));

  # Probes use the public domain, or the container directly for mesh-only ones.
  gatusEndpointOf =
    node:
    lib.findFirst (
      e:
      lib.hasPrefix "https://${node.domain}" e.url
      || lib.hasPrefix "http://${node.ip}:${toString (node.port or 0)}/" e.url
    ) null gatusEndpoints;

  # Only what Caddy serves under a name; the dashboard doesn't link to itself.
  linked = lib.filterAttrs (
    id: n: n ? meta && n ? domain && n ? externalPort && (n.enabled or true) && id != "dashboard"
  ) nodes;

  mkService =
    id: node:
    let
      endpoint = gatusEndpointOf node;
    in
    {
      inherit id;
      inherit (node.meta) name;
      category = node.meta.category or "Other";
      description = node.meta.description or "";
      url = "https://${node.domain}";
      host = hostOf node;
      network =
        if node.public or false then
          "public"
        else if node.meshOnly or false then
          "mesh"
        else
          "lan";
    }
    // lib.optionalAttrs (node.meta ? icon) { inherit (node.meta) icon; }
    // lib.optionalAttrs (endpoint != null) { gatusEndpoint = endpoint.name; };

  mkHost =
    id: h:
    {
      inherit id;
      name = id;
      ip = h.physicalIp or h.ip;
      role = lib.concatStringsSep ", " (h.tags or [ ]);
    }
    // lib.optionalAttrs (h ? system) { arch = lib.removeSuffix "-linux" h.system; };
in
{
  title = "kleinbem";
  subtitle = "Fleet launchpad";
  welcomeTitle = "Welcome home";
  welcomeSubtitle = "Every service of the fleet, with live health from Gatus.";
  # Proxied by the dashboard container (my.containers.dashboard.gatusUrl).
  gatusUrl = "/";
  weather = {
    latitude = 53.35;
    longitude = -6.26;
    label = "Dublin";
  };
  hosts = lib.mapAttrsToList mkHost (lib.filterAttrs (_: h: h ? ip) hosts);
  services = lib.mapAttrsToList mkService linked;
  # Pinned for every device; personal ones stay in the browser ("+ Add Link").
  links = [
    {
      name = "Claude";
      url = "https://claude.ai";
      icon = "✳️";
    }
    {
      name = "My pull requests";
      url = "https://github.com/pulls";
      icon = "🔀";
    }
    {
      name = "kleinbem repos";
      url = "https://github.com/kleinbem?tab=repositories";
      icon = "🐙";
    }
    {
      name = "Nixpkgs watch";
      url = "https://github.com/kleinbem/nix-packages/issues/276";
      icon = "👀";
    }
    {
      name = "NixOS search";
      url = "https://search.nixos.org/packages";
      icon = "❄️";
    }
    {
      name = "Mesh-LLM";
      url = "https://github.com/Mesh-LLM/mesh-llm";
      icon = "🕸️";
    }
  ];
  footerLinks = [
    {
      label = "status";
      url = "https://${nodes.gatus.domain}";
    }
    {
      label = "source";
      url = "https://github.com/kleinbem-dev/foyer";
    }
  ];
}
