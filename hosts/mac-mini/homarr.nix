# Homarr dashboard (start page), moving from the archived v0 line to v2.
#
# v2 has no importer for v0 data: the "Import from Homarr before 1.0" step
# was dropped in v2.0.0, v1.77.2 is the last release with it. So the move runs
# in two deploys:
#   "import": v0 stays on :7575, v1.77.2 runs on :7576 on the new appdata.
#             Export the ZIP from v0, import it into v1.
#   "v2":     v0 and v1 are gone, v2 runs on :7575 on the same appdata and
#             migrates the v1 database on start.
# The v0 dirs (configs, icons, data) are never touched, for rollback.
{
  config,
  lib,
  secretFile,
  ...
}:
let
  stage = "import"; # "import" | "v2"

  # Without the key the new containers can't start (Homarr exits without
  # SECRET_ENCRYPTION_KEY), so keep the v0 container until it exists.
  hostSops = secretFile "nix/per-host/mac-mini.yaml";
  hasKey =
    builtins.pathExists hostSops
    && lib.hasInfix "\nhomarr_secret_encryption_key:" ("\n" + builtins.readFile hostSops);

  appdata = "/var/lib/homarr/appdata";

  newHomarr = image: port: {
    inherit image;
    ports = [ "${toString port}:7575" ];
    volumes = [ "${appdata}:/appdata" ];
    environmentFiles = [ config.sops.templates."homarr.env".path ];
  };

  legacy = {
    image = "ghcr.io/ajnart/homarr:latest";
    ports = [ "7575:7575" ];
    volumes = [
      "/var/lib/homarr/configs:/app/data/configs"
      "/var/lib/homarr/icons:/app/public/icons"
      "/var/lib/homarr/data:/data"
    ];
  };
in
{
  assertions = [
    {
      assertion = lib.elem stage [
        "import"
        "v2"
      ];
      message = "hosts/mac-mini/homarr.nix: stage must be \"import\" or \"v2\"";
    }
  ];

  sops = lib.mkIf hasKey {
    secrets.homarr_secret_encryption_key.sopsFile = hostSops;
    templates."homarr.env" = {
      content = ''
        SECRET_ENCRYPTION_KEY=${config.sops.placeholder.homarr_secret_encryption_key}
      '';
      restartUnits = [
        (if stage == "import" then "podman-homarr-import.service" else "podman-homarr.service")
      ];
    };
  };

  virtualisation.oci-containers.containers =
    if !hasKey then
      { homarr = legacy; }
    else if stage == "import" then
      {
        homarr = legacy;
        homarr-import = newHomarr "ghcr.io/homarr-labs/homarr:v1.77.2" 7576;
      }
    else
      { homarr = newHomarr "ghcr.io/homarr-labs/homarr:v2.12.0" 7575; };

  systemd.tmpfiles.rules = [
    "d /var/lib/homarr 0755 root root - -"
    "d /var/lib/homarr/configs 0755 root root - -"
    "d /var/lib/homarr/icons 0755 root root - -"
    "d /var/lib/homarr/data 0755 root root - -"
    "d ${appdata} 0700 root root - -"
  ];

  environment.persistence."/nix/persist".directories = [ "/var/lib/homarr" ];
}
