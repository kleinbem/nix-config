# Keeps ~/.pki/caddy-root.crt and Chrome's NSS trust in sync with core-pi's
# Caddy local CA, so a CA rotation there doesn't break *.kleinbem.dev here.
# Uses a no-touch key (modules/nixos/keys.nix `caddy-ca-refresh`, restricted to
# reading the cert) because a timer can't answer a FIDO2 touch.
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

    # A fresh profile (Chrome never run) has no NSS db yet.
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
