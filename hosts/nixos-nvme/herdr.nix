# Phone pushes from herdr when an agent is blocked or done, on its own topic
# so agent chatter stays out of fleet alerts. Gated on the key name so this
# evals before the secret exists. Mint it with:
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
