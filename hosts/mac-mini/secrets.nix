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
  contactFile = inputs.nix-secrets + "/personas-contact.nix";
  personas = import ../../lib/personas.nix {
    inherit lib;
    contact = if builtins.pathExists contactFile then import contactFile else { };
  };
in
{
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";

    # Persistent host key generated during provisioning (provision-common.sh
    # pc_host_identity) — same convention as every other real host.
    age.keyFile = "/nix/persist/var/lib/sops/age/host.txt";

    # Don't fail eval/CI against the dummy secrets.yaml override.
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
      # Same field in the same shared secrets.yaml hass-pi already
      # decrypted this from; no re-encryption needed for mac-mini's own
      # age recipient (it already decrypts netbird_setup_key/
      # attic_pull_token from this exact file).
      discord_bot_token = { };
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
