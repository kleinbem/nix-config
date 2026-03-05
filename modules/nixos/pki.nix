# pki.nix — Internal PKI for mTLS between containers.
# Generates a root CA and per-container certificates on first boot.
# Certificates are persisted in /nix/persist/pki/internal/.
{
  pkgs,
  lib,
  myInventory,
  ...
}:

let
  pkiDir = "/nix/persist/pki/internal";
  caSubject = "/CN=NixOS Internal CA/O=kleinbem";
  certDays = "3650"; # 10 years (internal only)

  # All container nodes from the inventory
  containerNodes = myInventory.network.nodes;

  # Generate a shell script fragment that creates a cert for one container
  mkCertGenScript =
    name: node:
    let
      inherit (node) ip;
    in
    ''
      if [ ! -f "${pkiDir}/certs/${name}.crt" ]; then
        echo "  Generating certificate for: ${name} (${ip})"
        ${pkgs.openssl}/bin/openssl req -new -nodes \
          -keyout "${pkiDir}/certs/${name}.key" \
          -out "/tmp/pki-${name}.csr" \
          -subj "/CN=${name}/O=kleinbem" \
          -addext "subjectAltName=DNS:${name},DNS:${name}.local,IP:${ip}"

        ${pkgs.openssl}/bin/openssl x509 -req \
          -in "/tmp/pki-${name}.csr" \
          -CA "${pkiDir}/ca.crt" \
          -CAkey "${pkiDir}/ca.key" \
          -CAcreateserial \
          -out "${pkiDir}/certs/${name}.crt" \
          -days ${certDays} \
          -extfile <(echo "subjectAltName=DNS:${name},DNS:${name}.local,IP:${ip}")

        chmod 644 "${pkiDir}/certs/${name}.crt"
        chmod 600 "${pkiDir}/certs/${name}.key"
        rm -f "/tmp/pki-${name}.csr"
      fi
    '';

  allCertScripts = lib.concatStringsSep "\n" (lib.mapAttrsToList mkCertGenScript containerNodes);

in
{
  # Ensure PKI directory structure exists
  systemd.tmpfiles.rules = [
    "d ${pkiDir} 0755 root root - -"
    "d ${pkiDir}/certs 0755 root root - -"
  ];

  # One-shot service: generate CA + certs on first boot (idempotent)
  systemd.services.internal-pki = {
    description = "Internal PKI — Generate CA and container certificates";
    wantedBy = [ "multi-user.target" ];
    before = lib.mapAttrsToList (name: _: "container@${name}.service") containerNodes;
    after = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = [ pkgs.openssl ];

    script = ''
      set -euo pipefail

      echo "🔐 Internal PKI: Checking certificate state..."

      # --- Generate CA if missing ---
      if [ ! -f "${pkiDir}/ca.crt" ]; then
        echo "  Generating Internal CA..."
        openssl req -new -x509 -nodes \
          -keyout "${pkiDir}/ca.key" \
          -out "${pkiDir}/ca.crt" \
          -days ${certDays} \
          -subj "${caSubject}"

        chmod 600 "${pkiDir}/ca.key"
        chmod 644 "${pkiDir}/ca.crt"
      fi

      # --- Generate shared client certificate (for inter-container mTLS) ---
      if [ ! -f "${pkiDir}/certs/client.crt" ]; then
        echo "  Generating shared client certificate..."
        openssl req -new -nodes \
          -keyout "${pkiDir}/certs/client.key" \
          -out "/tmp/pki-client.csr" \
          -subj "/CN=internal-client/O=kleinbem"

        openssl x509 -req \
          -in "/tmp/pki-client.csr" \
          -CA "${pkiDir}/ca.crt" \
          -CAkey "${pkiDir}/ca.key" \
          -CAcreateserial \
          -out "${pkiDir}/certs/client.crt" \
          -days ${certDays}

        chmod 644 "${pkiDir}/certs/client.crt"
        chmod 600 "${pkiDir}/certs/client.key"
        rm -f "/tmp/pki-client.csr"
      fi

      # --- Generate per-container server certificates ---
      ${allCertScripts}

      echo "✅ Internal PKI: All certificates ready."
    '';
  };

  # Trust the internal CA system-wide on the host (handled via explicit path in apps)
  # security.pki.certificateFiles = [ "${pkiDir}/ca.crt" ];
}
