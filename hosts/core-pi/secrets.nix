{ inputs, config, ... }:
{
  sops = {
    defaultSopsFile = "${inputs.nix-secrets}/secrets.yaml";
    defaultSopsFormat = "yaml";
    validateSopsFiles = false;

    secrets = {
      # Identity (Authelia)
      authelia_session_secret = { };
      authelia_jwt_secret = { };
      authelia_storage_encryption_key = { };

      # Attic Binary Cache
      attic_server_token_rs256 = { };
      # Read-only pull token — activates modules/nixos/attic-pull.nix (netrc
      # Bearer auth + NetBird routing). Without it the host gets 401 from the
      # private cache and the nightly upgrade rebuilds the linux-rpi kernel
      # on-device until RuntimeMaxSec kills it.
      attic_pull_token = { };

      # GitHub Runner (optional)
      github_runner_pat = {
        mode = "0440";
        group = "wheel";
      };
    };

    templates = {
      "attic.env" = {
        mode = "0444";
        content = ''
          ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="${config.sops.placeholder.attic_server_token_rs256}"
        '';
      };
    };
  };
}
