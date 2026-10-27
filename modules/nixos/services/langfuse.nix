{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.langfuse;
in
{
  options.services.langfuse = {
    enable = lib.mkEnableOption "Langfuse server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.langfuse;
      description = "The Langfuse package to use.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "langfuse";
      description = "User account under which Langfuse runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "langfuse";
      description = "Group account under which Langfuse runs.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port to listen on.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to start the Langfuse systemd services automatically at boot.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        File containing environment variables for Langfuse.
        Must contain DATABASE_URL, NEXTAUTH_SECRET, etc.
      '';
    };

    clickhouse = {
      enable = lib.mkEnableOption "Clickhouse support for Langfuse";
      address = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Clickhouse server address.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.users."${cfg.user}" = {
      isSystemUser = true;
      inherit (cfg) group;
      home = "/var/lib/langfuse";
      createHome = true;
    };

    users.groups."${cfg.group}" = { };

    systemd.services.langfuse = {
      description = "Langfuse Web Server";
      after = [
        "network.target"
        "postgresql.service"
      ];
      wantedBy = lib.mkIf cfg.autoStart [ "multi-user.target" ];

      environment = {
        PORT = toString cfg.port;
        HOSTNAME = "0.0.0.0";
        NODE_ENV = "production";
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        EnvironmentFile = cfg.environmentFile;
        ExecStart = lib.getExe' cfg.package "langfuse-web";
        Restart = "always";
        StateDirectory = "langfuse";
        WorkingDirectory = "/var/lib/langfuse";

        # Hardening
        ProtectSystem = "full";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.services.langfuse-worker = {
      description = "Langfuse Background Worker";
      after = [
        "network.target"
        "postgresql.service"
        "langfuse.service"
      ];
      wantedBy = lib.mkIf cfg.autoStart [ "multi-user.target" ];

      environment = {
        NODE_ENV = "production";
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        EnvironmentFile = cfg.environmentFile;
        ExecStart = lib.getExe' cfg.package "langfuse-worker";
        Restart = "always";
        WorkingDirectory = "/var/lib/langfuse";

        # Hardening
        ProtectSystem = "full";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    # Optional Clickhouse local instance if enabled (common for small setups)
    services.clickhouse = lib.mkIf cfg.clickhouse.enable {
      enable = true;
    };
  };
}
