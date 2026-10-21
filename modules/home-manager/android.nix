{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.android;

  matepadBin = pkgs.writeShellScriptBin "matepad" ''
    set -euo pipefail

    SERIAL="QBK6R20825000010"
    ADB="${pkgs.android-tools}/bin/adb -s ''${SERIAL}"

    check_device() {
      if ! ${pkgs.android-tools}/bin/adb devices | grep -q "''${SERIAL}.*device"; then
        echo "Error: Tablet ''${SERIAL} is not connected or unauthorized." >&2
        ${pkgs.android-tools}/bin/adb devices
        exit 1
      fi
    }

    cmd_status() {
      check_device
      echo "=== Huawei MatePad Pro (MRX-W09) Status ==="
      
      echo -e "\n[Battery & Power]"
      $ADB shell dumpsys battery | awk '
        /AC powered:/ { ac=$3 }
        /USB powered:/ { usb=$3 }
        /level:/ { lvl=$2 }
        /temperature:/ { temp=$2/10 }
        /status:/ { st=($2==5?"Full":( $2==2?"Charging":"Discharging" )) }
        END { printf "  Status: %s (Level: %s%%, Temp: %.1f°C, AC: %s, USB: %s)\n", st, lvl, temp, ac, usb }
      '
      
      echo -e "\n[ADB Reverse Tunnels]"
      local tunnels
      tunnels=$($ADB reverse --list)
      if [ -n "$tunnels" ]; then
        echo "$tunnels" | sed 's/^/  /'
      else
        echo "  (No reverse tunnels active)"
      fi
      
      echo -e "\n[Shizuku Daemon]"
      if $ADB shell ps -ef | grep -q "shizuku_server"; then
        local pid
        pid=$($ADB shell ps -ef | grep "shizuku_server" | awk '{print $2}' | head -n 1)
        echo "  Running (PID: ''${pid})"
      else
        echo "  Stopped (Run 'matepad shizuku' or 'just android::start-shizuku' to start)"
      fi
      
      echo -e "\n[Power Safety Guardrail]"
      if $ADB shell pm list packages -d | grep -q "com.google.android.googlequicksearchbox"; then
        echo "  OK: Google Search spinloop is disabled"
      else
        echo "  WARNING: Google Search is ENABLED! Risk of 100% CPU battery drain!"
        echo "  Fix with: adb shell pm disable-user --user 0 com.google.android.googlequicksearchbox"
      fi
      
      echo -e "\n[Foreground Window]"
      local fg
      fg=$($ADB shell "dumpsys window | grep -E 'mCurrentFocus' | tail -n 1" | sed 's/^[[:space:]]*//')
      echo "  ''${fg}"
    }

    cmd_tunnels() {
      check_device
      echo "Ensuring ADB tunnels..."
      $ADB forward tcp:4747 tcp:4747
      $ADB reverse tcp:1701 tcp:1701
      $ADB reverse tcp:3389 tcp:3389
      echo "Reverse tunnels active:"
      $ADB reverse --list | sed 's/^/  /'
      echo "Forward tunnels active:"
      $ADB forward --list | sed 's/^/  /'
    }

    cmd_shizuku() {
      check_device
      if $ADB shell ps -ef | grep -q "shizuku_server"; then
        echo "Shizuku server is already running."
      else
        echo "Starting Shizuku server..."
        $ADB shell '
          APK_PATH=$(pm path moe.shizuku.privileged.api 2>/dev/null | cut -d: -f2 | head -n 1)
          if [ -n "$APK_PATH" ]; then
            LIB_DIR="$(dirname "$APK_PATH")/lib/arm64"
            if [ -f "$LIB_DIR/libshizuku.so" ]; then
              "$LIB_DIR/libshizuku.so"
            fi
          fi
        '
        sleep 1
        if $ADB shell ps -ef | grep -q "shizuku_server"; then
          echo "Shizuku server successfully started."
        else
          echo "Failed to start Shizuku server." >&2
          exit 1
        fi
      fi
    }

    cmd_install() {
      check_device
      local target="''${1:-}"
      if [ -z "$target" ]; then
        echo "Usage: matepad install <file.apk | package_id>" >&2
        exit 1
      fi
      
      if [ -f "$target" ]; then
        echo "Installing local APK: $target"
        $ADB install -r -d "$target"
        echo "Installation complete!"
      else
        echo "Treating '$target' as package ID. Fetching via apkeep..."
        local cache_dir="/tmp/apkeep_cache"
        mkdir -p "$cache_dir"
        
        if ${pkgs.apkeep}/bin/apkeep -d f-droid -a "$target" "$cache_dir" 2>/dev/null; then
          echo "Downloaded from F-Droid."
        elif ${pkgs.apkeep}/bin/apkeep -d apk-pure -a "$target" -o "acknowledge_dangers=true" "$cache_dir" 2>/dev/null; then
          echo "Downloaded from APKPure."
        else
          echo "Failed to download $target via apkeep. Provide APK file or download via Aurora Store." >&2
          exit 1
        fi
        
        local apk_file
        apk_file=$(find "$cache_dir" -name "''${target}*.apk" | head -n 1)
        if [ -n "$apk_file" ] && [ -f "$apk_file" ]; then
          echo "Installing $apk_file..."
          $ADB install -r -d "$apk_file"
          echo "Installation complete!"
          rm -f "$apk_file"
        else
          echo "Could not find downloaded APK." >&2
          exit 1
        fi
      fi
    }

    cmd_devcheck() {
      check_device
      echo "Granting DevCheck elevated permissions..."
      $ADB shell pm grant flar2.devcheck android.permission.BATTERY_STATS || true
      $ADB shell pm grant flar2.devcheck android.permission.DUMP || true
      $ADB shell pm grant flar2.devcheck android.permission.PACKAGE_USAGE_STATS || true
      $ADB shell cmd appops set flar2.devcheck moe.shizuku.manager.permission.API_V23 allow || true
      echo "Launching DevCheck..."
      $ADB shell monkey -p flar2.devcheck -c android.intent.category.LAUNCHER 1 >/dev/null
      echo "DevCheck running."
    }

    case "''${1:-status}" in
      status) cmd_status ;;
      tunnels) cmd_tunnels ;;
      shizuku) cmd_shizuku ;;
      install) shift; cmd_install "$@" ;;
      devcheck) cmd_devcheck ;;
      help|--help|-h)
        echo "Usage: matepad <command>"
        echo "Commands:"
        echo "  status     - Show tablet battery, thermals, reverse tunnels, and Shizuku status"
        echo "  tunnels    - Ensure reverse tunnels (1701 Weylus, 3389 RDP, 4747 DroidCam) are active"
        echo "  shizuku    - Verify or start the Shizuku privilege server"
        echo "  install    - Headless APK install from local file or package ID via apkeep"
        echo "  devcheck   - Grant diagnostics permissions and launch DevCheck"
        ;;
      *)
        echo "Unknown command: $1. Run 'matepad help' for usage." >&2
        exit 1
        ;;
    esac
  '';
in
{
  options.modules.android = {
    enable = lib.mkEnableOption "Android user tools (apkeep, matepad CLI, tablet management)";
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = [
        pkgs.apkeep
        matepadBin
      ];

      shellAliases = {
        tablet-status = "matepad status";
      };
    };
  };
}
