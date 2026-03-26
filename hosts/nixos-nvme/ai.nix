{ myInventory, lib, ... }:

{
  my.containers = {
    vllm = {
      enable = false;
      image = "docker.io/vllm/vllm-openai-cpu:latest-x86_64"; # Official bit-accurate CPU image
      ip = "${myInventory.network.nodes.vllm.ip}/24";
      hostDataDir = "/var/lib/images/vllm";
      device = "cpu"; # Switched back to CPU to trigger memory cap and stabilize hang
      model = "Qwen/Qwen2.5-Coder-32B-Instruct-GPTQ-Int4";
      quantization = "gptq"; # Reverted from Marlin due to missing ops crash
      enforceEager = true; # Bypass buggy graph warmup phase
      maxModelLen = 16384;
      memoryLimit = "48G"; # Plenty for 4-bit model
      memorySwapMax = "0"; # Prevent leaking into zram
      autoStart = true; # Restore autostart now that RAM is clear

      openvinoDevice = "GPU"; # Use Intel iGPU
      openvinoKvCacheSpace = 12;
      gpuMemoryUtilization = 0.5; # Reduced to prevent misallocation in CPU mode
      extraArgs = [
        "--tensor-parallel-size"
        "1"
      ];
      tls.whitelistDomains = [
        "huggingface.co"
        "cdn-lfs.huggingface.co"
      ];
    };

    litellm = {
      enable = true;
      ip = "${myInventory.network.nodes.litellm.ip}/24";
      hostDataDir = "/var/lib/images/litellm";
      autoStart = false; # Manual start for safety
      tls = {
        enable = true;
        serverPort = 4000;
      };
      backends = [
        {
          name = "qwen-32b-ollama";
          url = "http://host.containers.internal:11434";
          model = "ollama/qwen2.5-coder:32b";
        }
        {
          name = "gemma-2b-orin";
          url = "http://10.85.46.104:8000/v1";
          model = "google/gemma-2b";
        }
        {
          name = "qwen-7b-rpi";
          url = "http://10.85.46.117:8000/v1";
          model = "Qwen/Qwen2.5-Coder-7B-Instruct";
        }
      ];
    };

    playground = {
      enable = true;
      ip = "${myInventory.network.nodes.playground.ip}/24";
      hostDataDir = "/var/lib/images/playground";
      # user = config.my.username; # Restored if needed, but 'martin' is hardcoded in some places anyway
      memoryLimit = "8G";
    };

    caddy = {
      enable = true;
      ip = "${myInventory.network.nodes.caddy.ip}/24";
      hostDataDir = "/var/lib/images/caddy";
      memoryLimit = "512M";
      tls = {
        enable = false; # Handled internally by caddy/default.nix to avoid sidecar conflict
        serverPort = 0;
        upstreams = [ ];
      };
    };

    monitoring = {
      enable = true;
      ip = "${myInventory.network.nodes.monitoring.ip}/24";
      hostDataDir = "/var/lib/images/monitoring";
      nodeTargets = [
        myInventory.hosts.nixos-nvme.ip
        myInventory.hosts.orin-nano.ip
        myInventory.hosts.rpi5-1.ip
        myInventory.hosts.rpi5-2.ip
        myInventory.hosts.router-1.ip
        myInventory.hosts.router-2.ip
      ];
      vllmTargets = [
        myInventory.network.nodes.vllm.ip
        "10.85.46.104" # Orin Nano vLLM Instance
        "10.85.46.117" # RPi 5 vLLM Instance
      ];
    };

    agent-zero = {
      enable = false;
      ip = "${myInventory.network.nodes.agent-zero.ip}/24";
      hostDataDir = "/var/lib/images/agent-zero";
      vllmUrl = "http://localhost:8000/v1"; # Via mTLS sidecar → vLLM
      tls = {
        enable = true;
        serverPort = 50001;
        upstreams = [
          {
            name = "vllm";
            target = myInventory.network.nodes.vllm.ip;
            port = 8000;
          }
        ];
      };
    };

    comfyui = {
      enable = true;
      ip = "${myInventory.network.nodes.comfyui.ip}/24";
      hostDataDir = "/var/lib/images/comfyui";
      autoStart = false; # Manual start to prevent thermal overload during pull
    };

    langflow = {
      enable = true;
      ip = "${myInventory.network.nodes.langflow.ip}/24";
      hostDataDir = "/var/lib/images/langflow";
      autoStart = false; # Manual start to prevent thermal overload during pull
    };

    langfuse = {
      enable = true;
      ip = "${myInventory.network.nodes.langfuse.ip}/24";
      hostDataDir = "/var/lib/images/langfuse";
      autoStart = false; # Manual start for safety
    };
  };

  # Ensure the data directories exist with correct permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/images/vllm 0777 root root - -"
    "d /var/lib/images/litellm 0777 root root - -"
    "d /var/lib/images/playground 0777 martin users - -"
    "d /var/lib/images/caddy 0777 root root - -"
    "d /var/lib/images/monitoring 0777 root root - -"
    "d /var/lib/images/monitoring/grafana 0777 root root - -"
    "d /var/lib/images/comfyui 0777 root root - -"
    "d /var/lib/images/langflow 0777 root root - -"
    "d /var/lib/images/langfuse 0777 root root - -"
    "d /var/lib/images/langfuse/db 0777 root root - -"
    "Z /var/lib/images/ollama 0777 ollama ollama - -"
  ];

  # -----------------------------------------------------
  # 100% NATIVE, DECLARATIVE OLLAMA CONFIGURATION
  # -----------------------------------------------------

  # 1. Statically declare the user so 'tmpfiles' can resolve it
  users.users.ollama = {
    isSystemUser = true;
    group = "ollama";
    description = "Ollama Service User";
  };
  users.groups.ollama = { };

  # 2. Enable Native Ollama for CPU-Optimized Inference
  services.ollama = {
    enable = true;
    host = "0.0.0.0"; # Allow containers like litellm to access it
    home = "/var/lib/images/ollama";
    models = "/var/lib/images/ollama/models";
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "-1"; # Keep models in memory indefinitely
    };
  };

  # 3. Disable DynamicUser and explicitly set the user so Systemd maps it correctly
  systemd.services.ollama = {
    wantedBy = lib.mkForce [ ]; # Disable auto-start on boot
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "ollama";
      Group = "ollama";
    };
  };

  # 4. Allow Podman containers on the cbr0 network to reach Ollama
  networking.firewall.interfaces."cbr0".allowedTCPPorts = [ 11434 ];
}
