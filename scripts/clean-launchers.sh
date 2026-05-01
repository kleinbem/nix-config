#!/usr/bin/env bash

# nix-config/scripts/clean-launchers.sh
# Identifies and removes .desktop files that point to missing binaries or profiles.

APP_DIR="$HOME/.local/share/applications"
DRY_RUN=true

if [[ $1 == "--apply" ]]; then
  DRY_RUN=false
fi

echo "🔍 Scanning for broken launchers in $APP_DIR..."

found_broken=false

for file in "$APP_DIR"/*.desktop; do
  [ -e "$file" ] || continue

  # Extract the Exec line
  exec_line=$(grep "^Exec=" "$file" | head -1 | cut -d'=' -f2-)

  if [ -z "$exec_line" ]; then
    continue
  fi

  # Handle quotes and extract the binary
  if [[ $exec_line =~ ^\"([^\"]+)\" ]]; then
    binary="${BASH_REMATCH[1]}"
  else
    binary=$(echo "$exec_line" | awk '{print $1}')
  fi

  is_broken=false
  reason=""

  # 1. Check if binary exists
  if ! command -v "$binary" >/dev/null 2>&1 && ! [ -x "$binary" ]; then
    is_broken=true
    reason="Binary not found ($binary)"
  fi

  # 2. Specifically for apps that use a -profile flag (like Firefox/FFPWA)
  # Skip for Chrome/Chromium as they use different profile flags (--profile-directory)
  # and ensure we only match standalone -profile or --profile flags.
  if [[ $binary != *"chrome"* && $binary != *"chromium"* ]] &&
    [[ " $exec_line " == *" -profile "* || " $exec_line " == *" -profile="* ||
      " $exec_line " == *" --profile "* || " $exec_line " == *" --profile="* ]]; then

    # Extract the path, ensuring it doesn't start with a dash (which would be another flag)
    profile_path=$(echo "$exec_line" | sed -E -n 's/.* --?profile[ =]+"??([^ "-][^ "]*)"??.*/\1/p')

    if [ -n "$profile_path" ] && [ ! -d "$profile_path" ]; then
      is_broken=true
      reason="Profile directory missing ($profile_path)"
    fi
  fi

  if [ "$is_broken" = true ]; then
    found_broken=true
    if [ "$DRY_RUN" = true ]; then
      echo "❌ [BROKEN] $(basename "$file") -> $reason"
    else
      echo "🗑️ Deleting $(basename "$file")..."
      rm "$file"
    fi
  fi
done

if [ "$found_broken" = false ]; then
  echo "✅ No broken launchers found."
elif [ "$DRY_RUN" = true ]; then
  echo ""
  echo "💡 Run with 'just clean-launchers --apply' to actually delete these files."
fi
