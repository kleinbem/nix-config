# Push new/changed Obsidian vault notes into AnythingLLM (mac-mini, already
# deployed — nix-presets/containers/anythingllm.nix) via its documented REST
# API. Replaces workspace-indexer.go, a bespoke tool that walked the vault,
# called Ollama's embeddings endpoint directly, and wrote a flat
# cosine-similarity JSON index — AnythingLLM already does parsing, chunking,
# embedding and vector search itself; this only needs to push files in.
#
# AnythingLLM has no watched-folder ingestion (checked live against the
# instance's own /api/docs OpenAPI spec, 2026-09-20) — every file has to go
# through a real API call, hence a script rather than a bare bind-mount. The
# script itself lives at users/martin/files/scripts/sync-vault-to-anythingllm.sh
# (same "live git checkout, not nix-store copy" convention as
# notes-maintenance.nix, so edits take effect without a rebuild).
#
# ─── ENABLING — one-time manual bootstrap (needs the UI, not Nix-doable) ────
#  1. http://<anythingllm ip>:3001 (see inventory.nix's "anythingllm" node)
#     → create a workspace (any name; note the slug AnythingLLM derives from
#     it and set `workspaceSlug` below if it isn't "vault").
#  2. Settings → API Keys → Generate New API Key.
#  3. sops kleinbem-secrets/nix/per-host/nixos-nvme.yaml — add
#     anythingllm_api_key: <the key from step 2>.
#  4. Flip `enable = true` below, deploy. Until then this is fully inert:
#     no secret declared, no systemd units, no footprint.
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
