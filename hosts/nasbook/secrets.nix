{
  config,
  lib,
  inputs,
  ...
}:
let
  secretHelpers = import ../../lib/secrets.nix { inherit lib inputs; };
in
{
  sops = {
    # Use host SSH keys for automated decryption
    age.sshKeyPaths = [ "/nix/persist/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      # Read-only Attic pull token — activates modules/nixos/attic-pull.nix so
      # nightly upgrades substitute the CI-built closure instead of building.
      attic_pull_token = { };
      # ntfy topic for autoUpgrade notifications, shared (nix/shared.yaml).
      ntfy_deploy_topic = { };
      paperless_password = { };
      restic_password = { };
      restic_system_password = { };
      rclone_config = { };
      # Lets the nix daemon fetch the private kleinbem-secrets repo (core.nix
      # includes it); unauthenticated archive fetches of a private repo 404.
      github_read_all_token = {
        mode = "0440";
        group = "wheel";
      };
      # For the netbird-autojoin oneshot (networking.nix). Without NetBird the
      # mesh-only cache.kleinbem.dev is unreachable.
      netbird_setup_key = { };
    }
    // lib.optionalAttrs config.my.containers.miniflux.oidc.enable (
      lib.mapAttrs (_: s: s // { mode = "0444"; }) (
        secretHelpers.mkPerContainerSecrets {
          container = "miniflux";
          keys = [ "oauth_client_secret" ];
        }
      )
    )
    // lib.optionalAttrs config.my.containers.stalwart.enable (
      secretHelpers.mkPerContainerSecrets {
        container = "stalwart";
        keys = [ "admin_password_hash" ];
      }
    )
    // lib.optionalAttrs config.my.containers.forgejo.enable (
      lib.mapAttrs (_: s: s // { uid = 990; }) (
        secretHelpers.mkPerContainerSecrets {
          container = "forgejo";
          keys = [
            "admin_password"
            "oauth_client_secret"
          ];
        }
      )
    );
  };
}
