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
  # Markers the runner's jobs write (group-writable for the runner only), and
  # the window's own state (root only).
  buildWindowDir = "/run/mesh-llm-build-window";
  buildWindowState = "/run/mesh-llm-build-window-state";
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
        SupplementaryGroups = [
          "video"
          "mesh-llm-build-window"
        ];
        # The nightly writes its end marker here (build window below).
        ReadWritePaths = [ buildWindowDir ];
      };
    };

    # The Orin's builds and the MeshLLM node don't fit into 8 GB together: on
    # the GPU the node's model is pinned unified memory (5.7 GB with
    # Qwen3-4B), and the CUDA build was OOM-killed on 2026-10-31. So a build
    # job opens a window: its first step writes `start` (the node stops), its
    # last step `done` (the node starts again). Jobs open it themselves
    # because GitHub starts the nightly schedule hours late and manual runs
    # come at any time. A fallback at 23:30 UTC starts the node if a job died
    # without writing `done`, unless a job is still running. Only a node the
    # window stopped is started again: one stopped by hand stays off.
    users.groups.mesh-llm-build-window = { };
    systemd = {
      tmpfiles.settings."10-mesh-llm-build-window" = {
        ${buildWindowDir}.d = {
          mode = "0770";
          user = "root";
          group = "mesh-llm-build-window";
        };
        ${buildWindowState}.d = {
          mode = "0700";
          user = "root";
          group = "root";
        };
      };
      services = {
        # A deploy (comin switch) must not start the stopped node in the
        # middle of a build: it did twice on 2026-10-31, and the build was
        # OOM-killed. So a switch leaves the node alone; it picks up a changed
        # unit when the window closes (or on a manual restart).
        mesh-llm.restartIfChanged = false;
        mesh-llm-build-window-start = {
          description = "Stop the MeshLLM node for a GPU runner build";
          serviceConfig.Type = "oneshot";
          script = ''
            rm -f ${buildWindowDir}/start ${buildWindowDir}/done
            if systemctl is-active --quiet mesh-llm.service; then
              touch ${buildWindowState}/stopped
              systemctl stop mesh-llm.service
            fi
          '';
        };
        mesh-llm-build-window-end = {
          description = "Start the MeshLLM node again after a GPU runner build";
          serviceConfig.Type = "oneshot";
          script = ''
            rm -f ${buildWindowDir}/done
            if [ -e ${buildWindowState}/stopped ]; then
              rm -f ${buildWindowState}/stopped
              systemctl restart mesh-llm.service
            fi
          '';
        };
        mesh-llm-build-window-fallback = {
          description = "Start the MeshLLM node if a GPU runner build died in its window";
          serviceConfig.Type = "oneshot";
          path = [ pkgs.procps ];
          # Not while a job still runs: it needs the window open.
          script = ''
            if ! pgrep -x Runner.Worker >/dev/null; then
              systemctl start mesh-llm-build-window-end.service
            fi
          '';
        };
      };
      paths = {
        mesh-llm-build-window-start = {
          wantedBy = [ "paths.target" ];
          pathConfig.PathExists = "${buildWindowDir}/start";
        };
        mesh-llm-build-window-end = {
          wantedBy = [ "paths.target" ];
          pathConfig.PathExists = "${buildWindowDir}/done";
        };
      };
      timers.mesh-llm-build-window-fallback = {
        wantedBy = [ "timers.target" ];
        timerConfig.OnCalendar = "*-*-* 23:30:00 UTC";
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
