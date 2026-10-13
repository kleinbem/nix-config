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

