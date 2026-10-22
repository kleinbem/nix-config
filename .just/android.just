import 'common.just'

set working-directory := ".."

# --- Android / Phone & Tablet Management ---

PHONE_SERIAL  := "R5CW617ZWCF"
TABLET_SERIAL := "QBK6R20825000010"
PHONE_IP      := "10.0.0.8"
TABLET_IP     := "10.0.0.215"
DHIRUJAAN_PHONE_SERIAL := "RFCT90BVPNE"
DHIRUJAAN_PHONE_IP     := "10.0.0.238"

# ==========================================
# SMART DISPATCHERS (The "Single Entry" way)
# ==========================================

[group("Phone")]
phone *args:
    @just android::scrcpy-dispatch "{{PHONE_SERIAL}}" "{{PHONE_IP}}" "16M" {{args}}

[group("Tablet")]
tablet *args:
    @just android::scrcpy-dispatch "{{TABLET_SERIAL}}" "{{TABLET_IP}}" "24M" {{args}}

[group("Tablet")]
tablet-desk:
    #!/usr/bin/env bash
    set -euo pipefail
    SERIAL="{{TABLET_SERIAL}}"
    echo "🖥️  Bringing MatePad Pro into Desk Companion mode..."

    # 1. Forward and reverse ADB ports over USB
    echo "🔌 Establishing USB port tunnels..."
    adb -s "$SERIAL" forward tcp:4747 tcp:4747   # DroidCam (Camera/Mic -> PC)
    adb -s "$SERIAL" reverse tcp:1701 tcp:1701   # Weylus (Touch/Stylus Canvas PC -> Tablet)
    adb -s "$SERIAL" reverse tcp:3389 tcp:3389   # GNOME Remote Desktop (Extended 3rd Desktop)

    # 2. Power & Display optimizations for desk companion use
    echo "⚡ Applying desk companion power settings..."
    adb -s "$SERIAL" shell settings put global stay_on_while_plugged_in 7
    adb -s "$SERIAL" shell "echo 80 > /sys/class/power_supply/Battery/charge_control_limit_max 2>/dev/null || settings put global UsercustomedMAXChargeValue 80"
    adb -s "$SERIAL" shell dumpsys deviceidle disable >/dev/null 2>&1 || true

    # 3. Start Shizuku if available
    just android::start-shizuku || true

    echo "✅ Desk companion active!"
    echo "   • DroidCam webcam/mic: adb port 4747 (use 'just android::tablet-cam')"
    echo "   • Weylus interactive canvas: http://localhost:1701 (use 'just android::tablet-screen')"
    echo "   • GNOME RDP 3rd screen: localhost:3389 via aFreeRDP (use 'just android::tablet-rdp')"
    echo "   • GSConnect / KDE Connect paired: clipboard & file sync active"

[group("Tablet")]
tablet-cam:
    #!/usr/bin/env bash
    set -euo pipefail
    SERIAL="{{TABLET_SERIAL}}"
    echo "📷 Launching DroidCam webcam bridge..."
    adb -s "$SERIAL" forward tcp:4747 tcp:4747
    adb -s "$SERIAL" shell am start -n com.dev47apps.droidcam/.DroidCam 2>/dev/null || true
    sleep 1
    if lsmod | grep -q v4l2loopback; then
        echo "🎥 Connecting video loopback to /dev/video10..."
        droidcam-cli 127.0.0.1 4747
    else
        echo "💡 v4l2loopback not currently loaded in kernel. Opening DroidCam GUI..."
        droidcam &
    fi

[group("Tablet")]
tablet-screen:
    #!/usr/bin/env bash
    set -euo pipefail
    SERIAL="{{TABLET_SERIAL}}"
    echo "🎨 Launching Weylus touch & stylus canvas..."
    adb -s "$SERIAL" reverse tcp:1701 tcp:1701
    if ! ss -tulpn | grep -q ":1701 "; then
        echo "🚀 Starting Weylus server..."
        weylus --wayland-support --no-gui --auto-start &
        sleep 1
    fi
    echo "📱 Opening canvas on tablet..."
    adb -s "$SERIAL" shell am start -a android.intent.action.VIEW -d "http://localhost:1701" com.android.chrome >/dev/null
    echo "✨ Weylus active on tablet screen with multi-touch & M-Pencil support."

[group("Tablet")]
tablet-rdp:
    #!/usr/bin/env bash
    set -euo pipefail
    SERIAL="{{TABLET_SERIAL}}"
    echo "🖥️  Configuring GNOME RDP extended desktop on tablet..."
    adb -s "$SERIAL" reverse tcp:3389 tcp:3389
    grdctl rdp enable 2>/dev/null || true
    grdctl rdp disable-view-only 2>/dev/null || true
    echo "📱 Launching aFreeRDP on tablet..."
    adb -s "$SERIAL" shell monkey -p com.freerdp.afreerdp -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
    echo "✨ Connect in aFreeRDP to: localhost (or 127.0.0.1:3389)"

[group("Tablet")]
tablet-status:
    #!/usr/bin/env bash
    if command -v matepad >/dev/null 2>&1; then
        matepad status
    else
        SERIAL="{{TABLET_SERIAL}}"
        echo "=== Huawei MatePad Pro (MRX-W09) Status ==="
        echo -e "\n[Battery & Power]"
        adb -s "$SERIAL" shell dumpsys battery | awk '
            /AC powered:/ { ac=$3 }
            /USB powered:/ { usb=$3 }
            /level:/ { lvl=$2 }
            /temperature:/ { temp=$2/10 }
            /status:/ { st=($2==5?"Full":( $2==2?"Charging":"Discharging" )) }
            END { printf "  Status: %s (Level: %s%%, Temp: %.1f°C, AC: %s, USB: %s)\n", st, lvl, temp, ac, usb }
        '
        echo -e "\n[ADB Reverse Tunnels]"
        tunnels=$(adb -s "$SERIAL" reverse --list)
        if [ -n "$tunnels" ]; then
            echo "$tunnels" | sed 's/^/  /'
        else
            echo "  (No reverse tunnels active)"
        fi
        echo -e "\n[Shizuku Daemon]"
        if adb -s "$SERIAL" shell ps -ef | grep -q "shizuku_server"; then
            pid=$(adb -s "$SERIAL" shell ps -ef | grep "shizuku_server" | awk '{print $2}' | head -n 1)
            echo "  Running (PID: $pid)"
        else
            echo "  Stopped (Run 'just android::start-shizuku' to start)"
        fi
        echo -e "\n[Power Safety Guardrail]"
        if adb -s "$SERIAL" shell pm list packages -d | grep -q "com.google.android.googlequicksearchbox"; then
            echo "  OK: Google Search spinloop is disabled"
        else
            echo "  WARNING: Google Search is ENABLED! Risk of 100% CPU battery drain!"
        fi
        echo -e "\n[Foreground Window]"
        fg=$(adb -s "$SERIAL" shell "dumpsys window | grep -E 'mCurrentFocus' | tail -n 1" | sed 's/^[[:space:]]*//')
        echo "  $fg"
    fi

[group("Tablet")]
tablet-install app:
    #!/usr/bin/env bash
    if command -v matepad >/dev/null 2>&1; then
        matepad install {{app}}
    elif command -v apkeep >/dev/null 2>&1; then
        TARGET="{{app}}"
        SERIAL="{{TABLET_SERIAL}}"
        if [ -f "$TARGET" ]; then
            adb -s "$SERIAL" install -r -d "$TARGET"
        else
            mkdir -p /tmp/apkeep_cache
            apkeep -d f-droid -a "$TARGET" /tmp/apkeep_cache 2>/dev/null || apkeep -d apk-pure -a "$TARGET" -o "acknowledge_dangers=true" /tmp/apkeep_cache
            APK=$(find /tmp/apkeep_cache -name "${TARGET}*.apk" | head -n 1)
            adb -s "$SERIAL" install -r -d "$APK"
            rm -f "$APK"
        fi
    else
        echo "Install apkeep or run 'just switch' to apply the updated Home Manager profile." >&2
        exit 1
    fi

[group("Tablet")]
tablet-devcheck:
    #!/usr/bin/env bash
    if command -v matepad >/dev/null 2>&1; then
        matepad devcheck
    else
        SERIAL="{{TABLET_SERIAL}}"
        adb -s "$SERIAL" shell pm grant flar2.devcheck android.permission.BATTERY_STATS || true
        adb -s "$SERIAL" shell pm grant flar2.devcheck android.permission.DUMP || true
        adb -s "$SERIAL" shell pm grant flar2.devcheck android.permission.PACKAGE_USAGE_STATS || true
        adb -s "$SERIAL" shell cmd appops set flar2.devcheck moe.shizuku.manager.permission.API_V23 allow || true
        adb -s "$SERIAL" shell monkey -p flar2.devcheck -c android.intent.category.LAUNCHER 1 >/dev/null
    fi

[group("Dhirujaan")]
dhirujaan *args:
    @just android::scrcpy-dispatch "{{DHIRUJAAN_PHONE_SERIAL}}" "{{DHIRUJAAN_PHONE_IP}}" "16M" {{args}}

# ==========================================
# PRIVATE HELPERS (Logic Core)
# ==========================================

[private]
scrcpy-dispatch serial ip bitrate *args:
    #!/usr/bin/env bash
    set -e
    MODE="usb"
    AUDIO_FLAG=""
    
    # Parse Arguments
    for arg in {{args}}; do
        case $arg in
            wireless) MODE="wireless" ;;
            silent)   AUDIO_FLAG="--no-audio" ;;
            dup)      AUDIO_FLAG="--audio-dup" ;;
            help|-h|--help)
                echo "📱 scrcpy Smart Dispatcher"
                echo "--------------------------------"
                echo "Usage: just <command> [options]"
                echo ""
                echo "Options:"
                echo "  wireless  - Connect via TCP/IP (auto-connects if needed)"
                echo "  silent    - Launch without audio (--no-audio)"
                echo "  dup       - Mirror audio on both device and PC (--audio-dup)"
                echo "  help      - Show this help menu"
                exit 0
                ;;
            *)
                echo "⚠️ Unknown option: $arg"
                echo "💡 Available options: wireless, silent, dup, help"
                exit 1
                ;;
        esac
    done

    # Auto-detect Mode if USB is missing
    if [ "$MODE" == "usb" ] && ! adb devices | grep -q "{{serial}}"; then
        echo "🔌 USB device {{serial}} not found. Falling back to wireless..."
        MODE="wireless"
    fi

    if [ "$MODE" == "wireless" ]; then
        echo "📡 Checking for device at {{ip}}..."
        if ! adb devices | grep -q "{{ip}}:5555"; then
            echo "🔄 Initializing wireless bridge..."
            adb -s {{serial}} tcpip 5555 2>/dev/null || true
            sleep 2
            adb connect {{ip}}
        fi
        echo "🚀 Launching Wireless scrcpy ({{bitrate}})..."
        scrcpy --tcpip={{ip}} --max-fps 60 --video-bit-rate {{bitrate}} --stay-awake --power-off-on-close $AUDIO_FLAG
    else
        echo "🚀 Launching USB scrcpy ({{bitrate}})..."
        scrcpy -s {{serial}} --max-fps 60 --video-bit-rate {{bitrate}} --stay-awake --power-off-on-close $AUDIO_FLAG
    fi

# ==========================================
# MAINTENANCE & UTILS
# ==========================================

[group("Maintenance")]
android-sync:
    @echo "🔄 Syncing phone configuration locks..."
    @nix flake lock --update-input nix-config
    @if ! jj diff --quiet 2>/dev/null; then \
        jj describe -m "chore(phone): sync nix-config lock" && jj new; \
        jj git push --allow-new; \
    else \
        echo "Already synced."; \
    fi

[group("Maintenance")]
android-deploy:
    @just android::android-sync
    @echo "📡 Triggering update on phone via ADB..."
    @adb -s {{PHONE_SERIAL}} shell "export PATH=\$PATH:/data/data/com.termux.nix/files/home/.nix-profile/bin; cd ~/nix && git pull && nix-on-droid switch --flake .#phone --impure"

[group("Maintenance")]
android-backup:
    @echo "📥 Fetching latest Nix-on-Droid backups..."
    @adb pull "/sdcard/Download/nix-on-droid-snapshot-*.tar" . || echo "No snapshot found."

# One-command Termux provisioning for connected phone or tablet
[group("Maintenance")]
termux-provision device="phone":
    #!/usr/bin/env bash
    set -euo pipefail
    DEV="{{device}}"
    SERIAL=$(adb devices | grep -v "List" | grep "device$" | head -n 1 | cut -f1)
    if [ -z "$SERIAL" ]; then
        echo "❌ No ADB device found. Connect device via USB or WiFi first."
        exit 1
    fi
    echo "📱 Pushing Termux provisioning script to $SERIAL ($DEV)..."
    adb -s "$SERIAL" push scripts/provision-termux.sh /sdcard/Download/setup-termux.sh
    adb -s "$SERIAL" shell am start -n com.termux/.app.TermuxActivity >/dev/null 2>&1 || true
    echo "⚡ Executing in Termux..."
    sleep 1
    adb -s "$SERIAL" shell input text "bash\\ /sdcard/Download/setup-termux.sh\\ $DEV"
    adb -s "$SERIAL" shell input keyevent 66
    echo "⏳ Waiting for key generation..."
    sleep 4
    PUB="/sdcard/Download/${DEV}_termux.pub"
    if adb -s "$SERIAL" pull "$PUB" /tmp/${DEV}_termux.pub 2>/dev/null; then
        echo ""
        echo "🔑 Extracted $DEV public key:"
        cat "/tmp/${DEV}_termux.pub"
        echo ""
        echo "Add this key to nix-config/modules/nixos/keys.nix to authorize it."
    fi

# Start Shizuku server via ADB on connected device (for silent Aurora Store updates)
[group("Maintenance")]
start-shizuku:
    #!/usr/bin/env bash
    set -euo pipefail
    SERIAL=$(adb devices | grep -v "List" | grep "device$" | head -n 1 | cut -f1)
    if [ -z "$SERIAL" ]; then
        echo "❌ No ADB device found."
        exit 1
    fi
    echo "⚡ Starting Shizuku on $SERIAL..."
    adb -s "$SERIAL" shell "
        APK_PATH=\$(pm path moe.shizuku.privileged.api 2>/dev/null | cut -d: -f2 | head -n 1)
        if [ -n \"\$APK_PATH\" ]; then
            LIB_DIR=\"\$(dirname \"\$APK_PATH\")/lib/arm64\"
            if [ -f \"\$LIB_DIR/libshizuku.so\" ]; then
                \"\$LIB_DIR/libshizuku.so\"
                echo \"✅ Shizuku started.\"
            else
                echo \"⚠️ libshizuku.so not found in \$LIB_DIR\"
            fi
        else
            echo \"⚠️ Shizuku is not installed on \$SERIAL.\"
        fi
    "


# Keeping the hub for discovery
[group("Hub")]
android-hub:
    #!/usr/bin/env bash
    CHOICES="phone\ntablet\ndhirujaan\nandroid-sync\nandroid-deploy\nandroid-backup"
    echo -e "$CHOICES" | fzf --header "📱 scrcpy Hub" --height 15 --reverse --preview "just --show {}" | xargs -r just

