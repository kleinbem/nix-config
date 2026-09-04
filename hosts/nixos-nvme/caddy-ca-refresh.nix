# Keeps ~/.pki/caddy-root.crt (trusted into Chrome/Chromium's NSS db directly
# by this file's own certutil calls below — nix-presets/pwa.nix's
# `trustFleetInternalCas` activation did this too before the PWA framework
# was removed (2026-09-04), but this script never depended on it, and into
# Firefox's policies.Certificates.Install) in sync with the Caddy container's
# actual local CA, which only ever lives on core-pi (the one host that runs
# it — see nix-config/modules/nixos/core.nix's PKI comment). Unlike core-pi,
# which can just copy the file locally in its own container postStart hook,
# nixos-nvme has to pull it over SSH since Caddy runs on a different physical
# host. Without this, a CA rotation on core-pi (container recreated/moved)
# would silently break every *.kleinbem.dev PWA here until someone noticed
# and copied the new cert by hand.
#
# Uses a dedicated, non-FIDO2 key (~/.ssh/id_ed25519_caddy_ca_refresh,
# generated once locally, private half never in the nix store; public half
# in modules/nixos/keys.nix as `caddy-ca-refresh`, authorized only on core-pi
# with a `command=`/`restrict` prefix so it can do nothing but read that one
# already-public cert file). A daily systemd --user timer can't wait for a
# touch prompt the way the main hardware-backed key would require — first
# attempt at this used the default agent identity and just hung forever.
{
  config,
  pkgs,
  myInventory,
  ...
}:
let
  coreHost = "martin@${myInventory.hosts.core-pi.ip}";
  remoteCert = "/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt";
  localCert = "${config.home.homeDirectory}/.pki/caddy-root.crt";
  refreshKey = "${config.home.homeDirectory}/.ssh/id_ed25519_caddy_ca_refresh";
  nssdb = "sql:${config.home.homeDirectory}/.pki/nssdb";

  refreshScript = pkgs.writeShellScript "refresh-caddy-root-ca" ''
    set -euo pipefail
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT

    if [ ! -f "${refreshKey}" ]; then
      echo "${refreshKey} missing — one-time setup step not done, skipping refresh" >&2
      exit 0
    fi

    if ! ${pkgs.openssh}/bin/ssh -o ConnectTimeout=5 -o BatchMode=yes \
        -o IdentitiesOnly=yes -i "${refreshKey}" \
        ${coreHost} "cat ${remoteCert}" > "$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then
      echo "core-pi unreachable or cert missing at ${remoteCert} — skipping refresh" >&2
      exit 0
    fi

    if ! cmp -s "$tmp" "${localCert}" 2>/dev/null; then
      cp "$tmp" "${localCert}"
      echo "Caddy internal root CA updated from core-pi"
    fi

    # This used to be pwa.nix's job (home.activation, ran once at build
    # activation, well before this timer's first tick). Now this script is
    # the only thing that touches the NSS db, so it has to be able to
    # create it from nothing too — a fresh profile (or one where Chrome
    # hasn't run yet) has no ~/.pki/nssdb at all.
    mkdir -p "${config.home.homeDirectory}/.pki"
    if [ ! -f "${config.home.homeDirectory}/.pki/nssdb/cert9.db" ]; then
      ${pkgs.nss.tools}/bin/certutil -N -d "${nssdb}" --empty-password
    fi

    ${pkgs.nss.tools}/bin/certutil -D -d "${nssdb}" -n "Caddy Internal CA" 2>/dev/null || true
    ${pkgs.nss.tools}/bin/certutil -A -d "${nssdb}" -t "C,," -n "Caddy Internal CA" -i "${localCert}"
  '';
in
{
  systemd.user.services.refresh-caddy-root-ca = {
    Unit.Description = "Refresh the locally-trusted copy of Caddy's internal root CA from core-pi";
    Service = {
      Type = "oneshot";
      ExecStart = "${refreshScript}";
    };
  };

  systemd.user.timers.refresh-caddy-root-ca = {
    Unit.Description = "Periodically refresh Caddy's internal root CA from core-pi";
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1d";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
