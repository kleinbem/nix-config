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
    i=0
    TANG_SERVERS=(
      ${lib.concatMapStringsSep "\n      " (s: "\"${s}\"") remoteTangServers}
    )
    while [ "$i" -lt 30 ]; do
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
      systemd = {
        enable = true;
        network = {
          enable = true;
          wait-online.ignoredInterfaces = [
            "wlan*"
            "wlo*"
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
          before = [ "cryptsetup-clevis-${cfg.luksDevice}.service" ];
          wantedBy = [ "cryptsetup-clevis-${cfg.luksDevice}.service" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            TimeoutStartSec = 120;
            ExecStart = waitForTang;
          };
        };

        services."cryptsetup-clevis-${cfg.luksDevice}" = {
          after = [ "wait-for-tang.service" ];
          wants = [ "wait-for-tang.service" ];
        };
      };

      clevis = {
        enable = true;
        useTang = true;
        devices."${cfg.luksDevice}".secretFile = cfg.secretFile;
      };
    };
  };
}
