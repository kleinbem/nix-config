# Phone pushes from the herdr server that runs here: an agent is blocked, or
# finished in a pane nobody is looking at (nix-presets herdr.nix,
# modules.herdr.ntfy). Its own topic, so agent chatter stays out of the
# fleet alert topic.
#
# Gated on the key name in the plaintext sops file, so this evals before the
# secret exists. Mint it with:
#   sops --set '["ntfy_agents_topic"] "agents-<random>"' nix/per-host/nixos-nvme.yaml
{
  config,
  lib,
  myInventory,
  secretFile,
  ...
}:

let
  hostSops = secretFile "nix/per-host/nixos-nvme.yaml";
  hasTopic =
    builtins.pathExists hostSops
    && lib.hasInfix "\nntfy_agents_topic:" ("\n" + builtins.readFile hostSops);
in
lib.mkIf hasTopic {
  sops.secrets.ntfy_agents_topic = {
    sopsFile = hostSops;
    owner = config.my.username;
    group = "users";
    mode = "0400";
  };

  home-manager.users.${config.my.username}.modules.herdr.ntfy = {
    url = "https://${myInventory.network.nodes.ntfy.domain}";
    topicFile = config.sops.secrets.ntfy_agents_topic.path;
  };
}
