# A MeshLLM node on a fleet host: services.mesh-llm from nix-packages
# (NixOS/nixpkgs#571722 as written), with the fleet's choices on top. The
# nodes form one unpublished mesh: the always-on orin-nano creates it and
# prints a join token at its first start; a workstation joins with that
# token from sops (`joinTokenSecret`) and serves its own models into the
# mesh. Every node's local API (http://127.0.0.1:9337/v1, OpenAI-compatible)
# routes to whichever node holds the model, so goose and friends talk to
# localhost on each host.
#
# Bootstrap, once per mesh (the only manual step):
#   journalctl -u mesh-llm on the creating node → the join token, into
#   `sops kleinbem-secrets/nix/per-host/<joining host>.yaml` as mesh_llm_join,
#   then set joinTokenSecret = "mesh_llm_join" on that host.
{
  config,
  lib,
  options,
  pkgs,
  inputs,
  secretFile,
  ...
}:

let
  cfg = config.my.services.meshLlm;
in
{
  imports = [ inputs.nix-packages.nixosModules.mesh-llm ];

  options.my.services.meshLlm = {
    enable = lib.mkEnableOption "a MeshLLM node serving local models into the fleet mesh";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.mesh-llm;
      defaultText = lib.literalExpression "pkgs.mesh-llm";
      example = lib.literalExpression "pkgs.mesh-llm-cuda";
      description = "mesh-llm with the native runtimes this host's GPU needs (Vulkan is always bundled).";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "Qwen3-8B-Q4_K_M" ];
      description = ''
        Models this node serves: names from MeshLLM's catalog (downloaded on
        first start) or paths to GGUF files. Empty lets MeshLLM pick a small
        default for the hardware.
      '';
    };

    meshPort = lib.mkOption {
      type = lib.types.port;
      default = 7842;
      description = "UDP port for the mesh's QUIC traffic, opened in the firewall.";
    };

    joinTokenSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "mesh_llm_join";
      description = ''
        Name of the key in this host's `nix/per-host/<host>.yaml` that holds
        the mesh's join token. `null` creates a mesh of its own (the first
        node) or keeps running standalone until the token exists in sops:
        declaring a missing sops key would freeze every other secret on the
        host.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start the node at boot. Off, it starts only with
        `systemctl start mesh-llm`: on a workstation, a big model's memory
        otherwise sits in swap all day, next to the desktop and its builds.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments for `mesh-llm serve`.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops = lib.mkIf (cfg.joinTokenSecret != null) {
      secrets.${cfg.joinTokenSecret}.sopsFile =
        secretFile "nix/per-host/${config.networking.hostName}.yaml";
      # systemd reads EnvironmentFile as root before dropping to the dynamic user.
      templates."mesh-llm.env".content = ''
        MESH_LLM_JOIN=${config.sops.placeholder.${cfg.joinTokenSecret}}
      '';
    };

    services.mesh-llm = {
      enable = true;
      inherit (cfg) package meshPort extraArgs;
      openFirewall = true;
      settings = lib.mkIf (cfg.models != [ ]) {
        version = 1;
        models = map (model: { inherit model; }) cfg.models;
      };
      environmentFile = lib.mkIf (cfg.joinTokenSecret != null) config.sops.templates."mesh-llm.env".path;
    };

    systemd.services.mesh-llm.wantedBy = lib.mkIf (!cfg.autoStart) (lib.mkForce [ ]);

    # The fleet's hosts run a tmpfs root (persistence.nix), and /var is a
    # few GB of RAM: the node's state directory holds its identity (which
    # join tokens stay valid), its config and the model cache, so it lives
    # on /nix/persist. Both hosts have room there; a dedicated data disk
    # can come later. DynamicUser puts the directory under /var/lib/private
    # (as tang's). Found the hard way on 2026-10-20: a 19 GB download into
    # the tmpfs.
    environment.persistence = lib.mkIf (options.environment ? persistence) {
      "/nix/persist".directories = [ "/var/lib/private/mesh-llm" ];
    };
  };
}
