{ pkgs, ... }:

let
  # Define your credentials here!
  user = "admin";
  pass = "admin"; # CHANGE THIS LATER!
  portDashboard = "8080";
  portConsole = "7681";
in
{
  environment.packages = with pkgs; [
    olivetin
    ttyd
    # Helper script to launch the dashboard and console in the background
    (pkgs.writeShellScriptBin "start-dashboard" ''
      echo "🚀 Starting Mobile Command Center..."

      # 1. Start OliveTin (Dashboard)
      olivetin -config /etc/olivetin/config.yaml > /tmp/olivetin.log 2>&1 &

      # 2. Start TTyd (Console)
      ttyd -p ${portConsole} -c ${user}:${pass} zsh > /tmp/ttyd.log 2>&1 &

      echo "✨ Dashboard: http://localhost:${portDashboard}"
      echo "✨ Console:   http://localhost:${portConsole}"
      echo "🔐 Credentials: ${user} / ${pass}"
    '')
  ];

  # --- OliveTin Configuration (The Buttons) ---
  environment.etc."olivetin/config.yaml".text = ''
    listenAddress: "0.0.0.0:${portDashboard}"

    # Simple auth
    auth:
      enabled: true
      username: "${user}"
      password: "${pass}"

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
}
