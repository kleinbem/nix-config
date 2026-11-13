# A Cadre local-inference node (services.cadre) with fleet defaults.
# orin-nano creates the mesh; other nodes join with its token, and each node's
# local API at 127.0.0.1:9337/v1 routes to whichever node holds the model.
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
  cfg = config.my.services.cadre;
in
{
  imports = [ inputs.cadre.nixosModules.default ];

  options.my.services.cadre = {
    enable = lib.mkEnableOption "a Cadre local-inference node in the fleet mesh";

    backend = lib.mkOption {
      type = lib.types.enum [
        "mesh"
        "ollama"
      ];
      default = "mesh";
      description = "Local inference backend: MeshLLM across the fleet mesh, or local Ollama.";
    };

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
      description = "Models this node serves; empty lets MeshLLM pick a small default for the hardware.";
    };

    meshPort = lib.mkOption {
      type = lib.types.port;
      default = 7842;
      description = "UDP port for the mesh's QUIC traffic, opened in the firewall.";
    };

    joinTokenSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "cadre_join";
      description = ''
        Key in this host's `nix/per-host/<host>.yaml` holding the mesh join token.
        `null` creates a mesh of its own until the key exists in sops, since a
        missing sops key freezes every other secret on the host.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start the backend at boot. Off, start it with `systemctl start mesh-llm`
        so a workstation's big model doesn't sit in swap next to builds.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments for `mesh-llm serve`.";
    };

    goose.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install system-wide goose and cadre CLI. Off by default: workstations get
        them via Home Manager, and `pkgs.cadre` pulls CPU `mesh-llm` onto CUDA nodes.
      '';
    };

    web = {
      enable = lib.mkEnableOption "the Cadre web dashboard service";

      port = lib.mkOption {
        type = lib.types.port;
        default = 8384;
        description = "Port to serve the Cadre web dashboard on.";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Listen IP address for the web dashboard.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops = lib.mkIf (cfg.joinTokenSecret != null) {
      secrets.${cfg.joinTokenSecret}.sopsFile =
        secretFile "nix/per-host/${config.networking.hostName}.yaml";
    };

    services.cadre = {
      enable = true;
      inherit (cfg)
        backend
        package
        models
        meshPort
        autoStart
        extraArgs
        ;
      openFirewall = true;
      joinFile =
        if cfg.joinTokenSecret != null then config.sops.secrets.${cfg.joinTokenSecret}.path else null;
      goose = {
        inherit (cfg.goose) enable;
      };
      web = {
        inherit (cfg.web) enable port listenAddress;
      };
    };

    # MeshLLM learns the GPU's CUDA architecture from nvidia-smi; without it on
    # PATH it silently serves on the CPU. On Jetson it comes from l4t-nvml.
    systemd.services.mesh-llm.path = lib.mkIf (
      cfg.backend == "mesh" && options.hardware ? nvidia-jetpack && config.hardware.nvidia-jetpack.enable
    ) [ pkgs.nvidia-jetpack.l4t-nvml ];

    # /var is tmpfs: persist DynamicUser state (node identity + model cache).
    environment.persistence = lib.mkIf (options.environment ? persistence) {
      "/nix/persist".directories =
        lib.optional (cfg.backend == "mesh") "/var/lib/private/mesh-llm"
        ++ lib.optional (cfg.backend == "ollama") "/var/lib/private/ollama"
        ++ map (name: "/var/lib/private/cadre-buzz-${name}") (
          lib.attrNames config.services.cadre.buzz.agents
        );
    };
  };
}
