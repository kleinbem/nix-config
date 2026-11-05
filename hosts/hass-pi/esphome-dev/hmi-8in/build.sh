#!/usr/bin/env bash
# Builds and flashes the HMI 8" panel with the toolchain it needs: ESPHome dev
# plus the mipi_csi camera PR, and the PPA fix for ESP-IDF 5.5.6. hass-pi's
# dashboard can't build this config.
#   build.sh compile | upload [--device 10.0.0.112|/dev/ttyACM0] | logs
# upload compiles first: ESPHome's own upload flashes whatever was built last.
set -euo pipefail

ESPHOME_DEV_REV=5f5a81434df4d47c3b9fb8d3927f11791a5bcbf6 # esphome dev
CAMERA_PR=19480
CAMERA_PR_REV=9b115eed2cbd9241442a26bed2d6d6300165767a
PYTHON=${PYTHON:-python3}
here=$(cd "$(dirname "$0")" && pwd)
cache=${XDG_CACHE_HOME:-$HOME/.cache}
src=$cache/esphome-dev/src venv=$cache/esphome-dev/venv build=$cache/esphome-dev/hmi-8in
secrets=${SECRETS:-$cache/esphome-dev/secrets.yaml}

[ -f "$secrets" ] || {
  echo "secrets.yaml missing at $secrets (copy of hass-pi's /var/lib/esphome/secrets.yaml)" >&2
  exit 1
}
secrets=$(realpath -- "$secrets") # the link below resolves from $build

want=$ESPHOME_DEV_REV+$CAMERA_PR_REV
if [ "$(cat "$cache/esphome-dev/rev" 2>/dev/null)" != "$want" ]; then
  rm -rf "$src" "$venv"
  git clone -q --filter=blob:none https://github.com/esphome/esphome "$src"
  git -C "$src" checkout -q "$ESPHOME_DEV_REV"
  git -C "$src" fetch -q origin "pull/$CAMERA_PR/head"
  git -C "$src" -c user.name=build -c user.email=build@localhost merge -q --no-edit "$CAMERA_PR_REV"
  "$PYTHON" -m venv "$venv"
  "$venv/bin/pip" install -q "$src"
  echo "$want" >"$cache/esphome-dev/rev"
fi

mkdir -p "$build"
chmod 700 "$cache/esphome-dev" "$build" # generated main.cpp holds Wi-Fi and API keys
cp "$here"/hmi-8in.yaml "$here"/c6_fw.h "$here"/stations.h "$here"/chime.wav "$build"/
ln -sfn "$secrets" "$build/secrets.yaml"
mkdir -p "$cache/esphome-dev/tmp"
export TMPDIR=$cache/esphome-dev/tmp # gcc's temp files overflow a small /tmp tmpfs
unset IDF_PATH                       # ESPHome would build that tree instead of the one patched below

# ESP-IDF is downloaded on the first compile; patch it once it's there.
patch_idf() {
  local idf=${ESPHOME_ESP_IDF_PREFIX:-$cache/esphome/idf}/frameworks/5.5.6
  [ -f "$idf/.esphome_extracted" ] || return 1 # ESPHome re-extracts a partial tree
  if ! grep -q 469aa16c "$idf/components/esp_driver_ppa/src/ppa_srm.c"; then
    patch -d "$idf" -p1 <"$here/idf-5.5.6-ppa-srm-469aa16c.patch"
  fi
}
cmd=${1:-compile}
if [ "$cmd" != logs ] && ! patch_idf; then
  "$venv/bin/esphome" compile "$build/hmi-8in.yaml" || true
  patch_idf
fi

cd "$build"
[ "$cmd" = upload ] && "$venv/bin/esphome" compile hmi-8in.yaml
exec "$venv/bin/esphome" "$cmd" hmi-8in.yaml "${@:2}"
