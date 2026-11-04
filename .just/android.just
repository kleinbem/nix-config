import 'common.just'

set working-directory := ".."

# ==============================================================================
# Android Fleet Management (Forwarded to kleinbem/android-config)
# Canonical owner: https://github.com/kleinbem/android-config
# ==============================================================================

# Show status across all Android fleet devices
[group("Fleet")]
status:
    @just -f ../android-config/Justfile status

# Apply declarative tuning (phone, tablet, dhirujaan, all)
[group("Fleet")]
tune target="all":
    @just -f ../android-config/Justfile tune {{target}}

# Start Shizuku server on all connected devices
[group("Fleet")]
start-shizuku:
    @just -f ../android-config/Justfile start-shizuku

# Provision Termux on connected device
[group("Fleet")]
termux-provision device="phone":
    @just -f ../android-config/Justfile termux-provision {{device}}

# Screen mirror via scrcpy (phone, tablet, dhirujaan)
[group("Mirror")]
scrcpy target="phone" *args:
    @just -f ../android-config/Justfile scrcpy {{target}} {{args}}

# Huawei MatePad Pro desk companion mode
[group("Tablet")]
tablet-desk:
    @just -f ../android-config/Justfile tablet-desk
