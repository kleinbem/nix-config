{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.containers.langgraph;
  inherit (inputs.nix-presets.lib) mkContainer;

  langgraphEnv = pkgs.python3.withPackages (
    ps: with ps; [
      langgraph
      langgraph-cli
      langgraph-checkpoint-sqlite
      langgraph-sdk
      fastapi
      uvicorn
      pydantic
      httpx
    ]
  );
in
{
  options.my.containers.langgraph = {
    enable = lib.mkEnableOption "LangGraph Agent Workflow Runtime Container";
    ip = lib.mkOption {
      type = lib.types.str;
      default = "10.85.46.111/24";
      description = "Container IP on the cbr0 bridge.";
    };
    hostDataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/images/langgraph";
      description = "Host directory holding persistent state.";
    };
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start the container automatically on boot.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8123;
      description = "Port to listen on inside the container.";
    };
    memoryLimit = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "4G";
      description = "Memory limit for the container.";
    };
  };

  config = lib.mkIf cfg.enable (mkContainer {
    inherit config;
    name = "langgraph";
    inherit cfg;
    innerConfig = {
      users.users.langgraph = {
        isSystemUser = true;
        group = "langgraph";
        home = "/var/lib/langgraph";
        createHome = true;
      };
      users.groups.langgraph = { };

      environment.systemPackages = [
        langgraphEnv
        pkgs.curl
      ];

      systemd.services.langgraph = {
        description = "LangGraph Agent API Server";
        after = [ "network.target" ];
        wantedBy = lib.mkIf cfg.autoStart [ "multi-user.target" ];

        environment = {
          PORT = toString cfg.port;
          HOST = "0.0.0.0";
          LANGGRAPH_DATA_DIR = "/var/lib/langgraph";
        };

        preStart = ''
          if [ ! -f /var/lib/langgraph/langgraph.json ]; then
            cat > /var/lib/langgraph/langgraph.json << 'EOF'
          {
            "dependencies": ["."],
            "graphs": {
              "agent": "./agent.py:graph"
            },
            "env": ".env"
          }
          EOF
            cat > /var/lib/langgraph/agent.py << 'EOF'
          from langgraph.graph import StateGraph, START, END

          builder = StateGraph(dict)
          builder.add_node("echo", lambda state: {"status": "ok", "message": "LangGraph runner active"})
          builder.add_edge(START, "echo")
          builder.add_edge("echo", END)
          graph = builder.compile()
          EOF
            touch /var/lib/langgraph/.env
            chown -R langgraph:langgraph /var/lib/langgraph
          fi
        '';

        serviceConfig = {
          User = "langgraph";
          Group = "langgraph";
          WorkingDirectory = "/var/lib/langgraph";
          ExecStart = "${langgraphEnv}/bin/langgraph dev --host 0.0.0.0 --port ${toString cfg.port} --no-browser --no-reload";
          Restart = "on-failure";
          RestartSec = "10s";

          # Hardening
          ProtectSystem = "full";
          ProtectHome = "read-only";
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };

      networking.firewall.allowedTCPPorts = [ cfg.port ];
    };
  });
}
