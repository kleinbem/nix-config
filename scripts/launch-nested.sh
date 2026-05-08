#!/usr/bin/env bash

# This script launches a nested lightweight Wayland session (Sway)
# for the user 'dhirujaan' in a window.

TARGET_USER="dhirujaan"

echo "🚀 Preparing nested session for $TARGET_USER..."

# 1. Allow the user to access the current Wayland/X11 display
xhost +local:$TARGET_USER > /dev/null

# 2. Launch the nested session
# We use sudo to switch user, and dbus-run-session to ensure a fresh D-Bus bus
# The '--unsupported-gpu' flag for sway is sometimes needed in VMs/Nested,
# but usually not on bare metal.
sudo -u $TARGET_USER -i \
    WAYLAND_DISPLAY=$WAYLAND_DISPLAY \
    DISPLAY=$DISPLAY \
    dbus-run-session -- sway

echo "✅ Session closed."
