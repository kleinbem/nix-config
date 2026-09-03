{
  inputs,
  config,
  lib,
  ...
}:
let
  # Which kleinbem-secrets/personas/<name>.yaml key holds the API key for
  # each tool persona-runtime knows how to run (nix-presets/containers/
  # persona-runtime.nix's toolSpecs — keep in sync when a new tool gets
  # wired in there). Declaring secrets via a loop over personas.nix rather
  # than one-off entries per persona is the point of the persona-runtime
  # redesign: adding a new invocable persona is "add them to personas.nix
  # with a tool already in this map", not "hand-write a new sops.secrets
  # block".
  toolApiKeyField = {
    gemini-cli = "gemini_api_key";
    claude-code = "anthropic_api_key";
  };
  invocablePersonas = lib.filterAttrs (_: p: toolApiKeyField ? ${p.tool}) (import ../../personas.nix);
  personaSopsFile = name: "${inputs.nix-secrets}/personas/${name}.yaml";

  # sops-install-secrets validates its ENTIRE manifest atomically before
  # writing anything — one declared secret whose key doesn't exist yet in
  # its sopsFile fails the install for every OTHER secret on the host too
  # (signing keys, tokens, unrelated personas), silently, leaving them all
  # frozen at their previous generation. Confirmed live 2026-08-09:
  # michael-gruber's anthropic_api_key was declared here before the real
  # key was added to kleinbem-secrets/personas/michael-gruber.yaml (needs
  # manual provisioning via the Anthropic Console — can't be automated,
  # see commit 9b35079) — validateSopsFiles=false does NOT cover this (it
  # only skips checking the FILE exists, not that the KEY inside it does),
  # so this silently broke juan-gonzalez's just-renamed signing key too
  # and crash-looped hermes-juan. sops yaml keeps top-level key NAMES in
  # cleartext (only values are ENC[...]), so checking for one doesn't need
  # decryption — skip declaring an api_key secret for a persona whose
  # sopsFile doesn't have that field yet instead of bricking the host's
  # other secrets until someone notices. persona-runtime.nix's own
  # `config.sops.secrets ? "persona_${name}_api_key"` check already
  # handles the resulting absence gracefully (null apiKeyPath, fails only
  # if/when that specific persona is invoked).
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
    defaultSopsFile = "${inputs.nix-secrets}/nix/shared.yaml";
    defaultSopsFormat = "yaml";

    # Persistent host key generated during provisioning (provision-common.sh
    # pc_host_identity) — same convention as every other real host.
    age.keyFile = "/nix/persist/var/lib/sops/age/host.txt";

    # Don't fail eval/CI against the dummy nix/shared.yaml override.
    validateSopsFiles = false;

    # martin_password (sops key: martin_password_hash) is already declared by
    # users/martin/nixos.nix, imported below.
    secrets = {
      # NetBird — consumed by modules/nixos/networking.nix → netbird-autojoin
      # oneshot. Same shared setup key as orin-nano/core-pi/hass-pi.
      netbird_setup_key = { };

      # Read-only Attic pull token — activates modules/nixos/attic-pull.nix
      # (netrc Bearer auth + NetBird-routed reads). Without this,
      # my.deploy.autoUpgrade.requireCache above is pointless: cache pulls
      # 401 and silently fall back to a local build on this slow CPU,
      # capped/retried forever by RuntimeMaxSec instead of ever succeeding.
      attic_pull_token = { };

      # Hermes Agent's Discord gateway bot token — moved from hass-pi
      # 2026-08-05, see hosts/mac-mini/default.nix my.containers.hermes.
      # Lives in kleinbem-secrets' per-host scope now (nix/per-host/mac-mini.yaml,
      # cutover 2026-08-07) rather than the old shared secrets.yaml.
      discord_bot_token = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/mac-mini.yaml";
      };

      # Comma-separated Discord user IDs allowed to talk to the Hermes bot
      # (see templates."hermes.env" below). A real sops secret as of
      # 2026-08-08, NOT derived from personas-contact.nix at Nix eval time
      # anymore — that required importing plaintext PII (names/emails/
      # Matrix IDs) into the build, which only worked via a deferred
      # exception (nix-secrets-legacy-contact input, now removed). To add
      # another persona's discord-id: `sops kleinbem-secrets/nix/per-host/
      # mac-mini.yaml`, edit hermes_discord_allowed_users to a comma-joined
      # list.
      hermes_discord_allowed_users = {
        sopsFile = "${inputs.nix-secrets}/nix/per-host/mac-mini.yaml";
      };

    }
    // lib.optionalAttrs config.my.containers.stalwart.enable {
      # Stalwart fallback-admin secret (`mkpasswd -m sha-512` hash, or
      # plaintext — Stalwart accepts either). Per-CONTAINER scope, not
      # per-host: the mail server is a fleet service that could migrate
      # hosts, so `nix/per-container/stalwart.yaml` (already encrypted to
      # martin + nixos_nvme + mac_mini via the .sops.yaml catch-all) keeps
      # the secret's location independent of which host runs it. Gated
      # behind `enable` for the same reason as nixos-nvme's
      # litellm_master_key: sops-install-secrets validates the whole
      # manifest atomically, so one declared-but-unprovisioned secret
      # freezes every other secret on the host.
      stalwart_admin_password_hash = {
        sopsFile = "${inputs.nix-secrets}/nix/per-container/stalwart.yaml";
      };
    }
    // personaRuntimeSecrets;

    templates."hermes.env" = {
      mode = "0444";
      content = ''
        DISCORD_BOT_TOKEN=${config.sops.placeholder.discord_bot_token}
        # By default the gateway denies everyone not listed here.
        DISCORD_ALLOWED_USERS=${config.sops.placeholder.hermes_discord_allowed_users}
      '';
    };
  };
}
