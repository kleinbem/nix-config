{
  inputs,
  config,
  lib,
  ...
}:
let
  # CI overrides the nix-secrets input with an empty dummy directory — same
  # workaround hass-pi's secrets.nix uses. lib/personas.nix renders missing
  # PII fields as "(private)", fine for a CI-only eval that never activates.
  #
  # DELIBERATE, TRACKED EXCEPTION (2026-08-07 cutover): still reads from the
  # nix-secrets-legacy-contact input (== the OLD nix-secrets repo), not the
  # main nix-secrets input (== kleinbem-secrets as of this cutover).
  # kleinbem-secrets' personas/contact.nix is sops-encrypted, but this file
  # is `import`ed directly at Nix eval time — sops ciphertext can't be
  # imported as Nix source. Properly fixing this means reworking contact
  # consumption to a sops-nix runtime-decrypt pattern (real PII deserves
  # that, not a plaintext mirror like initrd/ got) — deferred, separate task.
  contactFile = inputs.nix-secrets-legacy-contact + "/personas-contact.nix";
  personas = import ../../lib/personas.nix {
    inherit lib;
    contact = if builtins.pathExists contactFile then import contactFile else { };
  };
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

      # Juan's persona git-signing identity. kleinbem-secrets stores personas
      # one-YAML-per-persona (cutover 2026-08-07) rather than nix-secrets' old
      # one-file-per-secret layout, so this is now a keyed value inside
      # personas/juan.yaml, not its own binary-mode sopsFile. Consumed by the
      # juan Hermes instance (hosts/mac-mini/default.nix
      # my.containers.hermes-juan) for git commit signing as that persona.
      juan_signing_key = {
        sopsFile = "${inputs.nix-secrets}/personas/juan.yaml";
        key = "id_ed25519";
        mode = "0400";
      };

      # Real Gemini backend for juan's Hermes worker (hermes-agent's native
      # Gemini adapter, not the local LiteLLM gateway) — see
      # nix-presets/containers/hermes-juan.nix's settings.model.
      # NOT YET REAL: gemini_api_key was never created for juan in either
      # secrets repo (rule/schema is wired, the actual credential is a
      # separate manual step — same status quo as before this cutover,
      # validateSopsFiles = false below keeps the build from failing on it).
      juan_gemini_api_key = {
        sopsFile = "${inputs.nix-secrets}/personas/juan.yaml";
        key = "gemini_api_key";
        mode = "0400";
      };
    };

    templates."hermes-juan.env" = {
      mode = "0444";
      content = ''
        GEMINI_API_KEY=${config.sops.placeholder.juan_gemini_api_key}
      '';
    };

    templates."hermes.env" = {
      mode = "0444";
      content = ''
        DISCORD_BOT_TOKEN=${config.sops.placeholder.discord_bot_token}
        # Comma-separated Discord user IDs allowed to talk to the bot. Sourced
        # from nix-secrets/personas-contact.nix (martin.discord-id) via
        # lib/personas.nix — add more personas' discord-id here as needed.
        # By default the gateway denies everyone not listed here.
        DISCORD_ALLOWED_USERS=${personas.all.martin.discord-id}
      '';
    };
  };
}
