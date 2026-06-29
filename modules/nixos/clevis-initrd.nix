{
  config,
  lib,
  pkgs,
  myInventory,
  ...
}:

let
  cfg = config.my.boot.clevis-initrd;

  # Generate list of remote Tang servers (filtering out our own IP if set)
  remoteTangServers =
    if cfg.hostIp != null then
      lib.filter (s: !lib.hasInfix cfg.hostIp s) myInventory.tangServers
    else
      myInventory.tangServers;

  waitForTang = pkgs.writeShellScript "wait-for-tang" ''
    has_carrier=false
    carrier_check=0
    while [ "$carrier_check" -lt 30 ]; do
      for pattern in ${cfg.networkInterface}; do
        for dev in /sys/class/net/$pattern; do
          if [ -e "$dev" ] && [ -f "$dev/carrier" ]; then
            if [ "$(cat "$dev/carrier" 2>/dev/null)" = "1" ]; then
              has_carrier=true
              break 2
            fi
          fi
        done
      done
      if [ "$has_carrier" = "true" ]; then
        break
      fi
      echo "wait-for-tang: Waiting for network carrier on ${cfg.networkInterface}... ($carrier_check)"
      ${pkgs.coreutils}/bin/sleep 1
      carrier_check=$((carrier_check + 1))
    done

    if [ "$has_carrier" = "false" ]; then
      echo "wait-for-tang: No network carrier detected on ${cfg.networkInterface}. Skipping Tang wait."
      echo "wait-for-tang: ${cfg.fallbackMessage}"
      exit 0
    fi

    i=0
    TANG_SERVERS=(
      ${lib.concatMapStringsSep "\n      " (s: "\"${s}\"") remoteTangServers}
    )
    while [ "$i" -lt 60 ]; do
      for server in "''${TANG_SERVERS[@]}"; do
        if ${pkgs.curl}/bin/curl -fsS -m 2 -o /dev/null "$server/adv"; then
          echo "wait-for-tang: Tang server $server reachable after $i retry(ies)"
          exit 0
        fi
      done
      echo "wait-for-tang: Tang servers not reachable yet ($i)"
      ${pkgs.coreutils}/bin/sleep 1
      i=$((i + 1))
    done
    echo "wait-for-tang: ${cfg.fallbackMessage}"
    exit 0
  '';
in
{
  options.my.boot.clevis-initrd = {
    enable = lib.mkEnableOption "Clevis auto-unlock with Tang in initrd";

    luksDevice = lib.mkOption {
      type = lib.types.str;
      description = "The LUKS device name to unlock (e.g. 'core_crypt').";
    };

    hostIp = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "The static IP address of the host in initrd. If null, DHCP is used.";
    };

    networkInterface = lib.mkOption {
      type = lib.types.str;
      default = "en* eth*";
      description = "The network interface name pattern for initrd.";
    };

    secretFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the JWE secret file.";
    };

    fallbackMessage = lib.mkOption {
      type = lib.types.str;
      default = "Timeout reached, continuing boot (clevis might fail)";
      description = "Message to show if Tang servers are unreachable.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      clevis
      jose
    ];

    boot.initrd = {
      # Add the secret JWE file to initrd
      secrets."/etc/clevis/${cfg.luksDevice}.jwe" = cfg.secretFile;

      systemd = {
        enable = true;
        network = {
          enable = true;
          wait-online.ignoredInterfaces = [
            "wlan0"
            "cbr0"
          ];
          networks."10-lan" = {
            matchConfig.Name = cfg.networkInterface;
            networkConfig =
              if cfg.hostIp != null then
                {
                  DHCP = "no";
                  Address = "${cfg.hostIp}/16";
                  Gateway = "10.0.0.1";
                }
              else
                {
                  DHCP = "yes";
                };
          };
        };

        storePaths = [ waitForTang ];

        services.wait-for-tang = {
          description = "Wait for Tang reachability before clevis LUKS unlock";
          after = [ "systemd-networkd.service" ];
          before = [ "clevis-jwe-unlock-${cfg.luksDevice}.service" ];
          wantedBy = [ "clevis-jwe-unlock-${cfg.luksDevice}.service" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            TimeoutStartSec = 120;
            ExecStart = waitForTang;
          };
        };

        services."clevis-jwe-unlock-${cfg.luksDevice}" = {
          description = "Unlock LUKS device ${cfg.luksDevice} using decrypted JWE secret";
          after = [ "wait-for-tang.service" ];
          wants = [ "wait-for-tang.service" ];
          before = [ "cryptsetup.target" ];
          wantedBy = [ "cryptsetup.target" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            echo "clevis-jwe-unlock: Starting unlock agent for ${cfg.luksDevice}..."
            JWE_FILE="/etc/clevis/${cfg.luksDevice}.jwe"
            if [ ! -f "$JWE_FILE" ]; then
              echo "clevis-jwe-unlock: JWE file $JWE_FILE not found. Exiting."
              exit 0
            fi

            if [ -e "/dev/mapper/${cfg.luksDevice}" ]; then
              echo "clevis-jwe-unlock: Device ${cfg.luksDevice} is already mapped. Exiting."
              exit 0
            fi

            # Attempt to decrypt the JWE file using clevis
            # Limit the time for clevis decrypt to 10 seconds to prevent hanging the boot
            echo "clevis-jwe-unlock: Attempting to decrypt JWE secret..."
            PASSPHRASE=$(${pkgs.coreutils}/bin/timeout 10 ${pkgs.clevis}/bin/clevis decrypt < "$JWE_FILE" 2>/dev/null || true)

            if [ -z "$PASSPHRASE" ]; then
              echo "clevis-jwe-unlock: Decryption failed or timed out (Tang offline/unreachable). Let fallback handle unlocking."
              exit 0
            fi

            echo "clevis-jwe-unlock: Decrypted passphrase successfully. Waiting for systemd password query for ${cfg.luksDevice}..."
            # Wait for the systemd ask-password query to appear (timeout after 30 seconds)
            for attempt in {1..120}; do
              if [ -e "/dev/mapper/${cfg.luksDevice}" ]; then
                echo "clevis-jwe-unlock: Device ${cfg.luksDevice} was unlocked by another agent. Exiting."
                exit 0
              fi
              for question in /run/systemd/ask-password/ask.*; do
                if [ -f "$question" ]; then
                  socket=""
                  device_id=""
                  while IFS= read -r line; do
                    case "$line" in
                      Id=cryptsetup:*) device_id="''${line##Id=cryptsetup:}" ;;
                      Socket=*) socket="''${line##Socket=}" ;;
                    esac
                  done < "$question"

                  if [ -n "$device_id" ] && [ -n "$socket" ] && [ -S "$socket" ]; then
                    echo "clevis-jwe-unlock: Found password query (Id: $device_id). Sending decrypted passphrase..."
                    if printf '%s' "$PASSPHRASE" | systemd-reply-password 1 "$socket"; then
                      echo "clevis-jwe-unlock: Successfully unlocked ${cfg.luksDevice} via systemd ask-password."
                      exit 0
                    else
                      echo "clevis-jwe-unlock: Failed to send passphrase to systemd-reply-password."
                    fi
                  fi
                fi
              done
              ${pkgs.coreutils}/bin/sleep 0.25
            done

            echo "clevis-jwe-unlock: Timeout waiting for systemd password query for ${cfg.luksDevice}."
            exit 0
          '';
        };
      };

      clevis = {
        enable = true;
        useTang = true;
      };
    };
  };
}
