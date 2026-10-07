#!/bin/sh
set -eu

mkdir -p \
    "${XDG_CONFIG_HOME:-/config/xdg/config}" \
    "${XDG_CACHE_HOME:-/config/xdg/cache}" \
    "${XDG_DATA_HOME:-/config/xdg/data}" \
    /output /storage /watch

echo "[HandBrake AMD] Starting GUI"
echo "[HandBrake AMD] VAAPI_DEVICE=${VAAPI_DEVICE:-/dev/dri/renderD128}"
echo "[HandBrake AMD] LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME:-auto}"

if [ -d /dev/dri ]; then
    echo "[HandBrake AMD] DRI devices:"
    ls -l /dev/dri || true

    DEVICE="${VAAPI_DEVICE:-/dev/dri/renderD128}"
    if [ -e "$DEVICE" ]; then
        echo "[HandBrake AMD] VA-API capabilities for $DEVICE:"
        vainfo --display drm --device "$DEVICE" 2>&1 || true
    else
        echo "[HandBrake AMD] WARNING: $DEVICE not found."
    fi
else
    echo "[HandBrake AMD] WARNING: /dev/dri is not mounted into the container."
fi

echo "[HandBrake AMD] HandBrake build:"
HandBrakeCLI --version 2>&1 || true

echo "[HandBrake AMD] Available VA-API encoders reported by HandBrake:"
HandBrakeCLI --help 2>&1 | grep -i -E 'vaapi|va-api' || true

exec /opt/handbrake/bin/ghb
