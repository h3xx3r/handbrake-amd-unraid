#!/usr/bin/env bash
set -Eeuo pipefail

APP_USER="app"
USER_ID="${USER_ID:-99}"
GROUP_ID="${GROUP_ID:-100}"
UMASK="${UMASK:-0022}"
DISPLAY="${DISPLAY:-:0}"
DISPLAY_WIDTH="${DISPLAY_WIDTH:-1920}"
DISPLAY_HEIGHT="${DISPLAY_HEIGHT:-1080}"
DISPLAY_DEPTH="${DISPLAY_DEPTH:-24}"
VNC_PASSWORD="${VNC_PASSWORD:-}"
KEEP_APP_RUNNING="${KEEP_APP_RUNNING:-1}"
VAAPI_DEVICE="${VAAPI_DEVICE:-/dev/dri/renderD128}"
WATCH_ENABLED="${WATCH_ENABLED:-1}"

log() {
    printf '[HandBrake AMD] %s\n' "$*"
}

cleanup() {
    log "Stopping services"
    kill "${WATCH_PID:-}" "${WEBSOCKIFY_PID:-}" "${VNC_PID:-}" "${OPENBOX_PID:-}" "${XVFB_PID:-}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

umask "$UMASK"

if getent group "$GROUP_ID" >/dev/null 2>&1; then
    PRIMARY_GROUP="$(getent group "$GROUP_ID" | cut -d: -f1)"
else
    groupmod -o -g "$GROUP_ID" "$APP_USER"
    PRIMARY_GROUP="$APP_USER"
fi
usermod -o -u "$USER_ID" -g "$PRIMARY_GROUP" "$APP_USER"

if [[ -d /dev/dri ]]; then
    while IFS= read -r gid; do
        [[ -n "$gid" ]] || continue
        if getent group "$gid" >/dev/null 2>&1; then
            gpu_group="$(getent group "$gid" | cut -d: -f1)"
        else
            gpu_group="gpu${gid}"
            groupadd -g "$gid" "$gpu_group" 2>/dev/null || true
        fi
        usermod -aG "$gpu_group" "$APP_USER" 2>/dev/null || true
    done < <(find /dev/dri -maxdepth 1 -type c -printf '%g\n' 2>/dev/null | sort -u)
fi

mkdir -p /config/xdg/config /config/xdg/cache /config/xdg/data /config/.vnc \
    /storage /output /watch /watch/done /watch/error /output/.handbrake-working
chown -R "$USER_ID:$GROUP_ID" /config
chown "$USER_ID:$GROUP_ID" /output /watch /watch/done /watch/error /output/.handbrake-working 2>/dev/null || true

log "GPU device: $VAAPI_DEVICE"
if [[ -e "$VAAPI_DEVICE" ]]; then
    vainfo --display drm --device "$VAAPI_DEVICE" 2>&1 | sed 's/^/[vainfo] /' || true
else
    log "WARNING: $VAAPI_DEVICE does not exist inside the container"
fi

log "Starting Xvfb ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}x${DISPLAY_DEPTH}"
gosu "$APP_USER" Xvfb "$DISPLAY" -screen 0 "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}x${DISPLAY_DEPTH}" -nolisten tcp -ac &
XVFB_PID=$!

for _ in $(seq 1 50); do
    [[ -S /tmp/.X11-unix/X0 ]] && break
    sleep 0.1
done

log "Starting Openbox"
gosu "$APP_USER" env DISPLAY="$DISPLAY" openbox &
OPENBOX_PID=$!

if [[ -n "$VNC_PASSWORD" ]]; then
    gosu "$APP_USER" x11vnc -storepasswd "$VNC_PASSWORD" /config/.vnc/passwd >/dev/null
    VNC_AUTH=( -rfbauth /config/.vnc/passwd )
else
    VNC_AUTH=( -nopw )
fi

log "Starting VNC on container port 5900"
gosu "$APP_USER" x11vnc -display "$DISPLAY" -forever -shared -rfbport 5900 -noxdamage "${VNC_AUTH[@]}" &
VNC_PID=$!

log "Starting noVNC on container port 5800"
gosu "$APP_USER" websockify --web=/usr/share/novnc/ 5800 localhost:5900 &
WEBSOCKIFY_PID=$!

if [[ "$WATCH_ENABLED" == "1" ]]; then
    log "Starting automatic watch-folder encoder"
    gosu "$APP_USER" env \
        HOME=/config \
        XDG_CONFIG_HOME=/config/xdg/config \
        XDG_CACHE_HOME=/config/xdg/cache \
        XDG_DATA_HOME=/config/xdg/data \
        LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}" \
        VAAPI_DEVICE="$VAAPI_DEVICE" \
        /watch-folder.sh &
    WATCH_PID=$!
else
    log "Watch-folder automation disabled (WATCH_ENABLED=$WATCH_ENABLED)"
fi

run_handbrake() {
    log "Starting HandBrake GTK"
    gosu "$APP_USER" env \
        DISPLAY="$DISPLAY" \
        HOME=/config \
        XDG_CONFIG_HOME=/config/xdg/config \
        XDG_CACHE_HOME=/config/xdg/cache \
        XDG_DATA_HOME=/config/xdg/data \
        LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}" \
        VAAPI_DEVICE="$VAAPI_DEVICE" \
        dbus-launch --exit-with-session /opt/handbrake/bin/ghb
}

if [[ "$KEEP_APP_RUNNING" == "1" ]]; then
    while true; do
        run_handbrake || true
        log "HandBrake exited; restarting in 2 seconds"
        sleep 2
    done
else
    run_handbrake
fi
