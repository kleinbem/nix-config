# Push changed Obsidian vault notes into AnythingLLM (mac-mini) over its REST
# API; it has no watched-folder ingestion. The script runs from the live
# checkout (users/martin/files/scripts/), so edits need no rebuild.
#
# One-time setup in the UI:
#  1. http://<anythingllm ip>:3001: create a workspace; set `workspaceSlug`
#     if its slug isn't "vault".
#  2. Settings → API Keys → generate a key, and add it as anythingllm_api_key
#     to kleinbem-secrets nix/per-host/nixos-nvme.yaml.
#  3. Enable and deploy.
{
  config,
  lib,
  pkgs,
  myInventory,
  ...
}:
let
  cfg = config.my.anythingllmVaultSync;
  node = myInventory.network.nodes.anythingllm;
  scripts = "/home/${config.my.username}/Develop/github.com/kleinbem/nix-config/users/martin/files/scripts";
in
{
  options.my.anythingllmVaultSync = {
    enable = lib.mkEnableOption "push Obsidian vault notes into AnythingLLM";
    workspaceSlug = lib.mkOption {
      type = lib.types.str;
      default = "vault";
      description = "AnythingLLM workspace slug created in step 1 of this file's header.";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${config.my.username} = {
      systemd.user.services.anythingllm-vault-sync = {
        Unit.Description = "Sync changed Obsidian vault notes into AnythingLLM";
        Service = {
          Type = "oneshot";
          Environment = [
            "ANYTHINGLLM_BASE_URL=http://${node.ip}:${toString node.port}"
            "ANYTHINGLLM_API_KEY_FILE=/run/secrets/anythingllm_api_key"
            "ANYTHINGLLM_WORKSPACE_SLUG=${cfg.workspaceSlug}"
            "PATH=${
              lib.makeBinPath [
                pkgs.bash
                pkgs.curl
                pkgs.jq
                pkgs.coreutils
                pkgs.findutils
              ]
            }"
          ];
          ExecStart = "${pkgs.bash}/bin/bash ${scripts}/sync-vault-to-anythingllm.sh";
        };
      };

      systemd.user.timers.anythingllm-vault-sync = {
        Unit.Description = "Periodically push vault changes into AnythingLLM";
        Timer = {
          OnBootSec = "15min";
          OnUnitActiveSec = "1h";
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
  };
}
