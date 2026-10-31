# GitHub Actions runner for kleinbem/mesh-llm-gpu: builds nixpkgs' mesh-llm
# for this Jetson's GPU and serves a model on it, the GPU half of the
# nix-packages canary, and builds any kleinbem flake attribute on demand
# (build.yaml: dispatch-only, commits on kleinbem branches only). The repo is
# private, so only its owner's workflows reach this machine; never attach the
# runner to a public repo.
#
# Turn on: create a fine-grained PAT (resource owner kleinbem, only
# kleinbem/mesh-llm-gpu, permission Administration: read and write), put it
# into `sops nix/per-host/orin-nano.yaml` as mesh_llm_gpu_runner_pat, then set
# my.services.meshLlmGpuRunner.enable on the host (orin-nano only: it
# relaxes the sandbox for the Jetson GPU nodes).
{
  config,
  lib,
  pkgs,
  secretFile,
  ...
}:

let
  cfg = config.my.services.meshLlmGpuRunner;
in
{
  options.my.services.meshLlmGpuRunner.enable =
    lib.mkEnableOption "the GitHub runner for the mesh-llm GPU tests (kleinbem/mesh-llm-gpu)";

  config = lib.mkIf cfg.enable {
    sops.secrets.mesh_llm_gpu_runner_pat.sopsFile = secretFile "nix/per-host/orin-nano.yaml";

    services.github-runners.mesh-llm-gpu = {
      enable = true;
      url = "https://github.com/kleinbem/mesh-llm-gpu";
      tokenFile = config.sops.secrets.mesh_llm_gpu_runner_pat.path;
      extraLabels = [
        "orin"
        "cuda"
      ];
      replace = true;
      # A fresh registration and work directory for every job.
      ephemeral = true;
      # Besides the module's bash, coreutils, git and nix: the canary script's
      # tools, and nvidia-smi (l4t-nvml), from which MeshLLM learns the GPU's
      # CUDA architecture; without it the CUDA runtime is rejected.
      extraPackages = with pkgs; [
        curl
        gawk
        gnugrep
        gnused
        jq
        nvidia-jetpack.l4t-nvml
        python3
      ];
      serviceOverrides = {
        # CUDA on Jetson goes through /dev/nvmap and the nvgpu nodes; a device
        # allow list blocks it silently (CPU fallback), as with services.mesh-llm.
        PrivateDevices = false;
        DeviceAllow = lib.mkForce [ ];
        ProtectClock = false;
        PrivateUsers = false;
        SupplementaryGroups = [ "video" ];
      };
    };

    nix.settings = {
      # Builds go to the SSD: /tmp is in RAM on this 8 GB host.
      build-dir = "/mnt/data/nix-build";
      # Parallel CUDA builds don't fit into 8 GB (core.nix allows 3 jobs).
      max-jobs = lib.mkForce 1;
      cores = lib.mkDefault 2;
    };
    systemd.tmpfiles.settings."10-mesh-llm-gpu-build-dir" = {
      "/mnt/data/nix-build".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
    };
  };
}
