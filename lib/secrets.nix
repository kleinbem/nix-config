# Reusable sops.secrets and template helpers for containers.
#
# Provides:
#   1. mkPerContainerSecrets: bulk secret generator for a container's YAML file
#   2. mkOidcSecret: plug-and-play Authentik OIDC client secret + template generator
{ lib, inputs }:
let
  mkPerContainerSecrets =
    {
      container,
      keys,
      # attr name prefix — defaults to `container` with hyphens turned into
      # underscores (e.g. "kleinbem-auth" -> "kleinbem_auth"), since Nix/sops-nix
      # attr names don't take hyphens the same way file/container names do.
      prefix ? lib.replaceStrings [ "-" ] [ "_" ] container,
      fullKey ? true,
    }:
    lib.listToAttrs (
      map (
        suffix:
        lib.nameValuePair "${prefix}_${suffix}" (
          {
            sopsFile = "${inputs.kleinbem-secrets}/nix/per-container/${container}.yaml";
          }
          // lib.optionalAttrs (!fullKey) { key = suffix; }
        )
      ) keys
    );

  # Helper for Authentik OIDC client secrets
  # Automatically handles existence checking so missing secrets don't freeze the host,
  # sets mode = "0444" so in-container unprivileged users can read it, and builds
  # the container env template.
  mkOidcSecret =
    {
      config,
      container,
      secretKey ? "${lib.replaceStrings [ "-" ] [ "_" ] container}_oauth_client_secret",
      yamlFile ? container,
      envTemplate ? "${container}.env",
      envVar ? "OAUTH_CLIENT_SECRET",
    }:
    let
      sopsFile = "${inputs.kleinbem-secrets}/nix/per-container/${yamlFile}.yaml";
      hasSecret =
        builtins.pathExists sopsFile && lib.hasInfix "\n${secretKey}:" ("\n" + builtins.readFile sopsFile);
    in
    {
      inherit
        hasSecret
        sopsFile
        secretKey
        envTemplate
        ;
      secrets = lib.optionalAttrs hasSecret {
        ${secretKey} = {
          inherit sopsFile;
          mode = "0444";
        };
      };
      templates = lib.optionalAttrs hasSecret {
        ${envTemplate} = {
          mode = "0444";
          content = ''
            ${envVar}=${config.sops.placeholder.${secretKey}}
          '';
        };
      };
    };
in
{
  __functor = _self: mkPerContainerSecrets;
  inherit mkPerContainerSecrets mkOidcSecret;
}
