#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${IMAGE:-ghcr.io/h3xx3r/handbrake-amd-unraid:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-HandBrake-AMD-GUI}"
CONFIG_PATH="${CONFIG_PATH:-/mnt/user/appdata/handbrake-amd}"
STORAGE_PATH="${STORAGE_PATH:-/mnt/user}"
OUTPUT_PATH="${OUTPUT_PATH:-/mnt/user/Media/HandBrake}"
WATCH_PATH="${WATCH_PATH:-/mnt/user/Media/HandBrake/watch}"
WEB_PORT="${WEB_PORT:-5800}"
VNC_PORT="${VNC_PORT:-5901}"
TZ="${TZ:-Europe/Berlin}"
USER_ID="${USER_ID:-99}"
GROUP_ID="${GROUP_ID:-100}"
UMASK="${UMASK:-0022}"
LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}"
VNC_PASSWORD="${VNC_PASSWORD:-}"
WATCH_ENABLED="${WATCH_ENABLED:-1}"
WATCH_PROFILE="${WATCH_PROFILE:-gui-default}"
WATCH_QUALITY="${WATCH_QUALITY:-24}"
WATCH_HANDBRAKE_PRESET="${WATCH_HANDBRAKE_PRESET:-}"
WATCH_POLL_SECONDS="${WATCH_POLL_SECONDS:-5}"
WATCH_SETTLE_SECONDS="${WATCH_SETTLE_SECONDS:-3}"

info() { printf '\n[HandBrake AMD] %s\n' "$*"; }
fail() { printf '\n[HandBrake AMD] ERROR: %s\n' "$*" >&2; exit 1; }
xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/"/\&quot;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
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
mkdir -p "$CONFIG_PATH" "$OUTPUT_PATH" "$WATCH_PATH" "$WATCH_PATH/done" "$WATCH_PATH/error"
[[ -d "$STORAGE_PATH" ]] || fail "STORAGE_PATH '$STORAGE_PATH' existiert nicht."

info "Lade Docker-Image: $IMAGE"
if ! docker pull "$IMAGE"; then
    cat >&2 <<'EOF'

Das Image konnte nicht geladen werden. Prüfe, ob das GHCR-Paket öffentlich ist
oder führe bei einem privaten Paket vorher 'docker login ghcr.io' aus.
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
    --label "net.unraid.docker.managed=dockerman"
    --label "net.unraid.docker.webui=http://[IP]:[PORT:5800]/"
    --label "net.unraid.docker.icon=https://handbrake.fr/img/logo.png"
    --label "net.unraid.docker.shell=bash"
    --device /dev/dri:/dev/dri
    -p "$WEB_PORT:5800"
    -p "$VNC_PORT:5900"
    -e "TZ=$TZ"
    -e "USER_ID=$USER_ID"
    -e "GROUP_ID=$GROUP_ID"
    -e "UMASK=$UMASK"
    -e "LIBVA_DRIVER_NAME=$LIBVA_DRIVER_NAME"
    -e "VAAPI_DEVICE=$VAAPI_DEVICE"
    -e "KEEP_APP_RUNNING=1"
    -e "WATCH_ENABLED=$WATCH_ENABLED"
    -e "WATCH_PROFILE=$WATCH_PROFILE"
    -e "WATCH_QUALITY=$WATCH_QUALITY"
    -e "WATCH_HANDBRAKE_PRESET=$WATCH_HANDBRAKE_PRESET"
    -e "WATCH_POLL_SECONDS=$WATCH_POLL_SECONDS"
    -e "WATCH_SETTLE_SECONDS=$WATCH_SETTLE_SECONDS"
    -v "$CONFIG_PATH:/config:rw"
    -v "$STORAGE_PATH:/storage:rw"
    -v "$OUTPUT_PATH:/output:rw"
    -v "$WATCH_PATH:/watch:rw"
)
[[ -n "$VNC_PASSWORD" ]] && RUN_ARGS+=( -e "VNC_PASSWORD=$VNC_PASSWORD" )
RUN_ARGS+=( "$IMAGE" )

info "Starte Container '$CONTAINER_NAME'"
"${RUN_ARGS[@]}" >/dev/null

TEMPLATE_DIR="/boot/config/plugins/dockerMan/templates-user"
if [[ -d "$TEMPLATE_DIR" ]]; then
    safe_name="${CONTAINER_NAME//[^A-Za-z0-9_.-]/-}"
    template_file="$TEMPLATE_DIR/my-${safe_name}.xml"
    x_config="$(xml_escape "$CONFIG_PATH")"
    x_storage="$(xml_escape "$STORAGE_PATH")"
    x_output="$(xml_escape "$OUTPUT_PATH")"
    x_watch="$(xml_escape "$WATCH_PATH")"
    x_vnc_password="$(xml_escape "$VNC_PASSWORD")"
    x_preset="$(xml_escape "$WATCH_HANDBRAKE_PRESET")"

    cat >"$template_file" <<EOF
<?xml version="1.0"?>
<Container version="2">
  <Name>$CONTAINER_NAME</Name>
  <Repository>$IMAGE</Repository>
  <Registry>https://ghcr.io/</Registry>
  <Network>bridge</Network>
  <Shell>bash</Shell>
  <Privileged>false</Privileged>
  <Support>https://github.com/h3xx3r/handbrake-amd-unraid/issues</Support>
  <Project>https://github.com/h3xx3r/handbrake-amd-unraid</Project>
  <Overview>HandBrake GTK mit AMD VA-API und automatischem Watch-Folder. Standardmäßig wird das in der GUI als Default markierte Preset verwendet.</Overview>
  <Category>MediaApp:Video</Category>
  <WebUI>http://[IP]:[PORT:5800]/</WebUI>
  <Icon>https://handbrake.fr/img/logo.png</Icon>
  <Config Name="Web GUI" Target="5800" Default="5800" Mode="tcp" Type="Port" Display="always" Required="true" Mask="false">$WEB_PORT</Config>
  <Config Name="VNC" Target="5900" Default="5901" Mode="tcp" Type="Port" Display="always" Required="false" Mask="false">$VNC_PORT</Config>
  <Config Name="AMD GPU" Target="/dev/dri" Default="/dev/dri" Mode="" Type="Device" Display="always" Required="true" Mask="false">/dev/dri</Config>
  <Config Name="Config" Target="/config" Default="/mnt/user/appdata/handbrake-amd" Mode="rw" Type="Path" Display="always" Required="true" Mask="false">$x_config</Config>
  <Config Name="Storage" Target="/storage" Default="/mnt/user" Mode="rw" Type="Path" Display="always" Required="true" Mask="false">$x_storage</Config>
  <Config Name="Output" Target="/output" Default="/mnt/user/Media/HandBrake" Mode="rw" Type="Path" Display="always" Required="true" Mask="false">$x_output</Config>
  <Config Name="Watch" Target="/watch" Default="/mnt/user/Media/HandBrake/watch" Mode="rw" Type="Path" Display="always" Required="true" Mask="false">$x_watch</Config>
  <Config Name="Watch Enabled" Target="WATCH_ENABLED" Default="1" Mode="" Type="Variable" Display="always" Required="true" Mask="false">$WATCH_ENABLED</Config>
  <Config Name="Watch Profile" Target="WATCH_PROFILE" Default="gui-default" Mode="" Type="Variable" Display="always" Required="true" Mask="false">$WATCH_PROFILE</Config>
  <Config Name="HandBrake Preset" Target="WATCH_HANDBRAKE_PRESET" Default="" Mode="" Type="Variable" Display="advanced" Required="false" Mask="false">$x_preset</Config>
  <Config Name="Watch Quality" Target="WATCH_QUALITY" Default="24" Mode="" Type="Variable" Display="advanced" Required="false" Mask="false">$WATCH_QUALITY</Config>
  <Config Name="Watch Poll Seconds" Target="WATCH_POLL_SECONDS" Default="5" Mode="" Type="Variable" Display="advanced" Required="false" Mask="false">$WATCH_POLL_SECONDS</Config>
  <Config Name="Watch Settle Seconds" Target="WATCH_SETTLE_SECONDS" Default="3" Mode="" Type="Variable" Display="advanced" Required="false" Mask="false">$WATCH_SETTLE_SECONDS</Config>
  <Config Name="Timezone" Target="TZ" Default="Europe/Berlin" Mode="" Type="Variable" Display="always" Required="true" Mask="false">$TZ</Config>
  <Config Name="User ID" Target="USER_ID" Default="99" Mode="" Type="Variable" Display="advanced" Required="true" Mask="false">$USER_ID</Config>
  <Config Name="Group ID" Target="GROUP_ID" Default="100" Mode="" Type="Variable" Display="advanced" Required="true" Mask="false">$GROUP_ID</Config>
  <Config Name="UMASK" Target="UMASK" Default="0022" Mode="" Type="Variable" Display="advanced" Required="false" Mask="false">$UMASK</Config>
  <Config Name="VAAPI Driver" Target="LIBVA_DRIVER_NAME" Default="radeonsi" Mode="" Type="Variable" Display="always" Required="true" Mask="false">$LIBVA_DRIVER_NAME</Config>
  <Config Name="VAAPI Device" Target="VAAPI_DEVICE" Default="/dev/dri/renderD128" Mode="" Type="Variable" Display="always" Required="true" Mask="false">$VAAPI_DEVICE</Config>
  <Config Name="VNC Password" Target="VNC_PASSWORD" Default="" Mode="" Type="Variable" Display="advanced" Required="false" Mask="true">$x_vnc_password</Config>
</Container>
EOF
    info "Unraid User-Template gespeichert: $template_file"
fi

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
HOST_IP="${HOST_IP:-UNRAID-IP}"

info "Installation abgeschlossen"
printf 'Container : %s\n' "$CONTAINER_NAME"
printf 'Web-GUI   : http://%s:%s\n' "$HOST_IP" "$WEB_PORT"
printf 'VNC       : %s:%s -> Container 5900\n' "$HOST_IP" "$VNC_PORT"
printf 'GPU       : %s\n' "$VAAPI_DEVICE"
printf 'Watch     : %s (Profilmodus %s)\n' "$WATCH_PATH" "$WATCH_PROFILE"
printf 'Output    : %s\n' "$OUTPUT_PATH"
printf '\nLogs anzeigen mit:\n  docker logs -f %s\n' "$CONTAINER_NAME"
