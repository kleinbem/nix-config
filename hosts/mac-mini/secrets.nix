{
  inputs,
  config,
  lib,
  secretFile,
  ...
}:
let
  mkPerContainerSecrets = import ../../lib/secrets.nix { inherit lib inputs; };

  # alertmanager-ntfy: the `monitoring` ntfy user's password plus the alert
  # topic. Gated on the key existing; sops-nix fails activation on a missing key.
  hostSops = secretFile "nix/per-host/mac-mini.yaml";
  hasMonitoringNtfy =
    builtins.pathExists hostSops
    && lib.hasInfix "\nntfy_monitoring_password:" ("\n" + builtins.readFile hostSops);

  # Gates keys that may not be provisioned yet, like personaHasField below.
  macMiniSopsFile = secretFile "nix/per-host/mac-mini.yaml";
  macMiniHasField = field: lib.hasInfix "\n${field}:" ("\n" + builtins.readFile macMiniSopsFile);

  secretHelpers = import ../../lib/secrets.nix { inherit lib inputs; };
  openWebUiOidc = secretHelpers.mkOidcSecret {
    inherit config;
    container = "open-webui";
    envTemplate = "openwebui.env";
  };

  # The personas/<name>.yaml key holding each tool's API key. Keep in sync
  # with persona-runtime.nix's toolSpecs; a new persona only needs an entry
  # in personas.nix with a tool listed here.
  toolApiKeyField = {
    gemini-cli = "gemini_api_key";
    claude-code = "anthropic_api_key";
  };
  invocablePersonas = lib.filterAttrs (_: p: toolApiKeyField ? ${p.tool}) (import ../../personas.nix);
  personaSopsFile = name: secretFile "personas/${name}.yaml";

  # sops-install-secrets checks its whole manifest at once: one declared key
  # missing from its file silently freezes every other secret on the host
  # (validateSopsFiles=false doesn't cover missing keys). Key names are
  # cleartext in sops yaml, so skip an api_key the file doesn't have yet;
  # persona-runtime treats it as absent until that persona is invoked.
  personaHasField =
    name: field:
    let
      file = personaSopsFile name;
    in
    builtins.pathExists file && lib.hasInfix "\n${field}:" ("\n" + builtins.readFile file);

  personaRuntimeSecrets = lib.listToAttrs (
    lib.concatMap (
      name:
      let
        apiField = toolApiKeyField.${invocablePersonas.${name}.tool};
      in
      [
        (lib.nameValuePair "persona_${name}_signing_key" {
          sopsFile = personaSopsFile name;
          key = "id_ed25519";
          mode = "0400";
        })
      ]
      ++ lib.optional (personaHasField name apiField) (
        lib.nameValuePair "persona_${name}_api_key" {
          sopsFile = personaSopsFile name;
          key = apiField;
          mode = "0400";
        }
      )
    ) (builtins.attrNames invocablePersonas)
  );
in
{
  sops = {
    # Host key generated during provisioning (provision-common.sh pc_host_identity).
    age.keyFile = "/nix/persist/var/lib/sops/age/host.txt";

    # martin_password (sops key: martin_password_hash) is already declared by
    # users/martin/nixos.nix, imported below.
    secrets = {
      # ntfy topic for autoUpgrade notifications, shared (nix/shared.yaml).
      ntfy_deploy_topic = { };
      # Shared setup key for the netbird-autojoin oneshot (networking.nix).
      netbird_setup_key = { };

      # Read-only Attic pull token (attic-pull.nix). Without it requireCache
      # pulls get 401 and fall back to slow local builds on this CPU.
      attic_pull_token = { };

      # Lets the nix daemon fetch the private kleinbem-secrets repo (core.nix
      # includes it); unauthenticated archive fetches of a private repo 404.
      github_read_all_token = {
        mode = "0440";
        group = "wheel";
      };

      # Hermes Agent's Discord gateway bot token.
      discord_bot_token = {
        sopsFile = secretFile "nix/per-host/mac-mini.yaml";
      };

      # Comma-separated Discord user IDs allowed to talk to the Hermes bot.
      # Kept in sops so the PII stays out of the build; edit
      # hermes_discord_allowed_users in nix/per-host/mac-mini.yaml to add one.
      hermes_discord_allowed_users = {
        sopsFile = secretFile "nix/per-host/mac-mini.yaml";
      };

    }
    // lib.optionalAttrs (macMiniHasField "cloudflare_dyndns_token") {
      # Cloudflare token (Zone:DNS:Edit on kleinbem.dev only, narrower than the
      # Terraform token) for cloudflare-dyndns, which keeps mail.kleinbem.dev
      # pointed at the dynamic PPPoE IP.
      cloudflare_dyndns_token = {
        sopsFile = macMiniSopsFile;
      };
    }
    // lib.optionalAttrs config.my.containers.monitoring.grafanaOidc.enable {
      # Authentik OIDC client secret for Grafana's login. Value comes from
      # `tofu output -raw grafana_oidc_client_secret` in nix/infra.
      # 0444, not mkPerContainerSecrets' 0400: grafana's in-container user
      # can't read a root-only bind mount, and its uid varies by package.
      monitoring_grafana_oauth_client_secret = {
        sopsFile = secretFile "nix/per-container/monitoring.yaml";
        mode = "0444";
      };
    }
    // lib.optionalAttrs config.my.containers.open-webui.oidc.enable openWebUiOidc.secrets
    // lib.optionalAttrs config.my.containers.stalwart.enable (
      # Stalwart fallback-admin secret (`mkpasswd -m sha-512` hash or plaintext).
      # Per-container scope so it can move hosts with the mail server.
      mkPerContainerSecrets {
        container = "stalwart";
        keys = [ "admin_password_hash" ];
      }
    )
    // lib.optionalAttrs config.my.containers.forgejo.enable (
      # Owned by uid 990, the forgejo user the preset pins inside the
      # container, so the bootstrap unit can read the bind mounts without
      # making them world-readable.
      lib.mapAttrs (_: s: s // { uid = 990; }) (mkPerContainerSecrets {
        container = "forgejo";
        keys = [
          "admin_password"
          "oauth_client_secret"
        ];
      })
    )
    // personaRuntimeSecrets;

    templates = {
      # Merged on top of alertmanager-ntfy's settings inside the monitoring
      # container (my.containers.monitoring.ntfy.authConfigFile).
      "alertmanager-ntfy.yml" = lib.mkIf hasMonitoringNtfy {
        mode = "0444";
        content = ''
          ntfy:
            auth:
              basic:
                username: monitoring
                password: ${config.sops.placeholder.ntfy_monitoring_password}
            notification:
              topic: ${config.sops.placeholder.ntfy_alert_topic}
        '';
      };
      "hermes.env" = {
        mode = "0444";
        content = ''
          DISCORD_BOT_TOKEN=${config.sops.placeholder.discord_bot_token}
          # By default the gateway denies everyone not listed here.
          DISCORD_ALLOWED_USERS=${config.sops.placeholder.hermes_discord_allowed_users}
        '';
      };
    }
    // lib.optionalAttrs config.my.containers.open-webui.oidc.enable openWebUiOidc.templates;
  };
}
