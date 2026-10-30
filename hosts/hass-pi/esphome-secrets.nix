# The ESPHome dashboard's secrets.yaml (what `!secret` in ./esphome/*.yaml
# reads), rendered from sops instead of hand-edited state:
#   - wifi_ssid / wifi_password: kleinbem-secrets shared/wifi.yaml, the same
#     file openwrt-config builds the 16CVG SSID from (one place to rotate it).
#   - api_key_* / ota_password: nix/per-host/hass-pi.yaml, prefixed esphome_;
#     a device whose key isn't there yet is left out.
# The dashboard serves secrets.yaml to anyone who can reach it, so all of this
# stays off until its login password (esphome_dashboard_password) exists too.
#
# Values reach the unit as systemd credentials and preStart writes the file
# with jq (JSON is valid YAML, and every value comes out quoted). A hand-made
# secrets.yaml already there is kept once as secrets.yaml.pre-sops.
{
  config,
  lib,
  pkgs,
  secretFile,
  ...
}:
let
  wifiSops = secretFile "shared/wifi.yaml";
  hostSops = secretFile "nix/per-host/hass-pi.yaml";
  has =
    file: key: builtins.pathExists file && lib.hasInfix "\n${key}:" ("\n" + builtins.readFile file);

  # !secret name → sops key in the host file. Add a line per new device.
  deviceKeys = lib.filterAttrs (_: has hostSops) {
    api_key_hmi_8in_1 = "esphome_api_key_hmi_8in_1";
    api_key_smart_86_box_1 = "esphome_api_key_smart_86_box_1";
    ota_password = "esphome_ota_password";
  };

  secrets = {
    wifi_ssid = {
      sopsFile = wifiSops;
      key = "wifi_ssid";
    };
    wifi_password = {
      sopsFile = wifiSops;
      key = "wifi_pass";
    };
  }
  // lib.mapAttrs (_: key: {
    sopsFile = hostSops;
    inherit key;
  }) deviceKeys;

  enabled =
    config.services.esphome.enable
    && has wifiSops "wifi_ssid"
    && has wifiSops "wifi_pass"
    && has hostSops "esphome_dashboard_password";
in
lib.mkIf enabled {
  sops.secrets =
    lib.mapAttrs' (
      name: s: lib.nameValuePair "esphome/${name}" (s // { restartUnits = [ "esphome.service" ]; })
    ) secrets
    // {
      "esphome/dashboard_password" = {
        sopsFile = hostSops;
        key = "esphome_dashboard_password";
      };
    };

  # Generated hex, so no quoting needed in the env file.
  sops.templates."esphome-dashboard.env" = {
    content = ''
      ESPHOME_USERNAME=martin
      ESPHOME_PASSWORD=${config.sops.placeholder."esphome/dashboard_password"}
    '';
    restartUnits = [ "esphome.service" ];
  };

  systemd.services.esphome = {
    serviceConfig = {
      EnvironmentFile = config.sops.templates."esphome-dashboard.env".path;
      LoadCredential = lib.mapAttrsToList (
        name: _: "${name}:${config.sops.secrets."esphome/${name}".path}"
      ) secrets;
    };
    preStart = lib.mkAfter ''
      s=/var/lib/esphome/secrets.yaml
      if [ -f "$s" ] && [ ! -e "$s.sops-managed" ]; then cp -p "$s" "$s.pre-sops"; fi
      ${lib.getExe pkgs.jq} -n ${
        lib.concatMapStringsSep " " (name: ''--rawfile ${name} "$CREDENTIALS_DIRECTORY/${name}"'') (
          lib.attrNames secrets
        )
      } '$ARGS.named' > "$s.new"
      chmod 0600 "$s.new"
      mv "$s.new" "$s"
      touch "$s.sops-managed"
    '';
  };
}
