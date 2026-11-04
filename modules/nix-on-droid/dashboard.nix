{ pkgs, ... }:

let
  portDashboard = "8080";
  portConsole = "7681";

  olivetinTemplate = pkgs.writeText "olivetin-template.yaml" ''
    listenAddress: "127.0.0.1:${portDashboard}"

    auth:
      enabled: true
      username: "@USERNAME@"
      password: "@PASSWORD@"

    actions:
      - title: "🔄 Sync & Switch"
        icon: "⚡"
        shell: "bash /home/nix-on-droid/scripts/phone-activate.sh"
        timeout: 600

      - title: "🛡️ Create Backup"
        icon: "💾"
        shell: "bash /home/nix-on-droid/scripts/phone-backup.sh"
        timeout: 300

      - title: "🧹 Nix Garbage Collect"
        icon: "🧹"
        shell: "nix-collect-garbage -d"
        timeout: 300

      - title: "📊 System Status"
        icon: "📱"
        shell: "termux-battery-status && df -h /data"
  '';
in
{
  environment.packages = with pkgs; [
    olivetin
    ttyd
    # Helper script to launch the dashboard and console in the background
    (pkgs.writeShellScriptBin "start-dashboard" ''
      echo "🚀 Starting Mobile Command Center..."

      AUTH_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/dashboard"
      AUTH_FILE="$AUTH_DIR/credentials"
      mkdir -p "$AUTH_DIR"
      if [ ! -f "$AUTH_FILE" ]; then
        (
          umask 077
          PASS=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
          echo "DASHBOARD_USER=admin" > "$AUTH_FILE"
          echo "DASHBOARD_PASS=$PASS" >> "$AUTH_FILE"
        )
        echo "🔑 Generated initial dashboard credentials at $AUTH_FILE"
      fi

      # shellcheck disable=SC1090
      source "$AUTH_FILE"
      USER="''${DASHBOARD_USER:-admin}"
      PASS="''${DASHBOARD_PASS}"

      if [ -z "$PASS" ]; then
        echo "ERROR: DASHBOARD_PASS is empty in $AUTH_FILE" >&2
        exit 1
      fi

      RUNTIME_CONFIG="''${XDG_RUNTIME_DIR:-/tmp}/olivetin-config.yaml"
      (
        umask 077
        sed -e "s|@USERNAME@|$USER|g" -e "s|@PASSWORD@|$PASS|g" \
          "${olivetinTemplate}" > "$RUNTIME_CONFIG"
      )

      # 1. Start OliveTin (Dashboard)
      olivetin -config "$RUNTIME_CONFIG" > /tmp/olivetin.log 2>&1 &

      # 2. Start TTyd (Console)
      ttyd -p ${portConsole} -c "$USER:$PASS" zsh > /tmp/ttyd.log 2>&1 &

      echo "✨ Dashboard: http://localhost:${portDashboard}"
      echo "✨ Console:   http://localhost:${portConsole}"
      echo "🔐 Logged in as: $USER (credentials in $AUTH_FILE)"
    '')
  ];
}
