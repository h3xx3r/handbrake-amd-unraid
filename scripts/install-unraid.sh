#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${IMAGE:-ghcr.io/h3xx3r/handbrake-amd-unraid:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-HandBrake-AMD-GUI}"
CONFIG_PATH="${CONFIG_PATH:-/mnt/user/appdata/handbrake-amd}"
STORAGE_PATH="${STORAGE_PATH:-/mnt/user}"
OUTPUT_PATH="${OUTPUT_PATH:-/mnt/user/Media/HandBrake}"
WATCH_PATH="${WATCH_PATH:-/mnt/user/Media/HandBrake/watch}"
WEB_PORT="${WEB_PORT:-5800}"
VNC_PORT="${VNC_PORT:-5900}"
TZ="${TZ:-Europe/Berlin}"
USER_ID="${USER_ID:-99}"
GROUP_ID="${GROUP_ID:-100}"
UMASK="${UMASK:-0022}"
LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}"
VNC_PASSWORD="${VNC_PASSWORD:-}"

info() {
    printf '\n[HandBrake AMD] %s\n' "$*"
}

fail() {
    printf '\n[HandBrake AMD] ERROR: %s\n' "$*" >&2
    exit 1
}

command -v docker >/dev/null 2>&1 || fail "Docker wurde nicht gefunden. Dieses Script ist für einen Unraid-Host mit aktiviertem Docker gedacht."
docker info >/dev/null 2>&1 || fail "Docker läuft nicht oder ist nicht erreichbar."

[[ -d /dev/dri ]] || fail "/dev/dri existiert nicht. Prüfe, ob die AMD-GPU vom Unraid-Host erkannt wird."

if [[ -z "${VAAPI_DEVICE:-}" ]]; then
    if [[ -e /dev/dri/renderD128 ]]; then
        VAAPI_DEVICE="/dev/dri/renderD128"
    else
        VAAPI_DEVICE="$(find /dev/dri -maxdepth 1 -type c -name 'renderD*' 2>/dev/null | sort | head -n 1 || true)"
    fi
fi

[[ -n "${VAAPI_DEVICE:-}" ]] || fail "Kein VA-API Render-Node unter /dev/dri gefunden."
[[ -e "$VAAPI_DEVICE" ]] || fail "VAAPI_DEVICE '$VAAPI_DEVICE' existiert nicht."

info "Verwende GPU-Gerät: $VAAPI_DEVICE"
info "Erstelle persistente Verzeichnisse"
mkdir -p "$CONFIG_PATH" "$OUTPUT_PATH" "$WATCH_PATH"
[[ -d "$STORAGE_PATH" ]] || fail "STORAGE_PATH '$STORAGE_PATH' existiert nicht."

info "Lade Docker-Image: $IMAGE"
if ! docker pull "$IMAGE"; then
    cat >&2 <<'EOF'

Das Image konnte nicht geladen werden.
Falls der erste GHCR-Build bereits erfolgreich war, prüfe auf GitHub unter
Packages -> handbrake-amd-unraid -> Package settings, ob das Paket auf Public
gestellt wurde. Bei einem privaten Paket ist vorher ein 'docker login ghcr.io'
nötig.
EOF
    exit 1
fi

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    info "Vorhandenen Container '$CONTAINER_NAME' ersetzen"
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

RUN_ARGS=(
    docker run -d
    --name "$CONTAINER_NAME"
    --restart unless-stopped
    --device "$VAAPI_DEVICE:$VAAPI_DEVICE"
    -p "$WEB_PORT:5800"
    -p "$VNC_PORT:5900"
    -e "TZ=$TZ"
    -e "USER_ID=$USER_ID"
    -e "GROUP_ID=$GROUP_ID"
    -e "UMASK=$UMASK"
    -e "LIBVA_DRIVER_NAME=$LIBVA_DRIVER_NAME"
    -e "VAAPI_DEVICE=$VAAPI_DEVICE"
    -e "KEEP_APP_RUNNING=1"
    -v "$CONFIG_PATH:/config:rw"
    -v "$STORAGE_PATH:/storage:rw"
    -v "$OUTPUT_PATH:/output:rw"
    -v "$WATCH_PATH:/watch:rw"
)

if [[ -n "$VNC_PASSWORD" ]]; then
    RUN_ARGS+=( -e "VNC_PASSWORD=$VNC_PASSWORD" )
fi

RUN_ARGS+=( "$IMAGE" )

info "Starte Container '$CONTAINER_NAME'"
"${RUN_ARGS[@]}" >/dev/null

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
HOST_IP="${HOST_IP:-UNRAID-IP}"

info "Installation abgeschlossen"
printf 'Container : %s\n' "$CONTAINER_NAME"
printf 'Web-GUI   : http://%s:%s\n' "$HOST_IP" "$WEB_PORT"
printf 'VNC       : %s:%s\n' "$HOST_IP" "$VNC_PORT"
printf 'GPU       : %s\n' "$VAAPI_DEVICE"
printf 'Config    : %s\n' "$CONFIG_PATH"
printf 'Output    : %s\n' "$OUTPUT_PATH"
printf '\nLogs anzeigen mit:\n  docker logs -f %s\n' "$CONTAINER_NAME"
printf '\nVA-API im Container prüfen mit:\n  docker exec -it %s sh -lc '\''vainfo --display drm --device "$VAAPI_DEVICE"'\''\n' "$CONTAINER_NAME"
