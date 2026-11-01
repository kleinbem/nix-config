# A MeshLLM node (services.mesh-llm from nix-packages) with fleet defaults.
# orin-nano creates the mesh; other nodes join with its token. Each node's
# local API at 127.0.0.1:9337/v1 routes to whichever node holds the model.
#
# Joining, once per mesh: copy the token from `journalctl -u mesh-llm` on the
# creating node into the joining host's per-host sops file as mesh_llm_join,
# then set joinTokenSecret = "mesh_llm_join" there.
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

    # MeshLLM learns the GPU's CUDA architecture from nvidia-smi; without it on
    # the service's PATH it silently serves on the CPU. On a Jetson,
    # nvidia-smi comes from l4t-nvml.
    systemd.services.mesh-llm.path = lib.optional (
      options.hardware ? nvidia-jetpack && config.hardware.nvidia-jetpack.enable
    ) pkgs.nvidia-jetpack.l4t-nvml;

    # /var is a small tmpfs, and the state dir holds the node identity and the
    # model cache, so persist it. DynamicUser puts it under /var/lib/private.
    environment.persistence = lib.mkIf (options.environment ? persistence) {
      "/nix/persist".directories = [ "/var/lib/private/mesh-llm" ];
    };
  };
}
