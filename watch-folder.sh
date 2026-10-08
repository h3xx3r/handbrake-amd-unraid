#!/usr/bin/env bash
set -Eeuo pipefail

WATCH_DIR="${WATCH_DIR:-/watch}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
WATCH_PROFILE="${WATCH_PROFILE:-rx6700-hevc10}"
WATCH_QUALITY="${WATCH_QUALITY:-24}"
WATCH_POLL_SECONDS="${WATCH_POLL_SECONDS:-5}"
WATCH_SETTLE_SECONDS="${WATCH_SETTLE_SECONDS:-3}"
WATCH_HANDBRAKE_PRESET="${WATCH_HANDBRAKE_PRESET:-Fast 1080p30}"
LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}"
VAAPI_DEVICE="${VAAPI_DEVICE:-/dev/dri/renderD128}"

DONE_DIR="$WATCH_DIR/done"
ERROR_DIR="$WATCH_DIR/error"
WORK_DIR="$OUTPUT_DIR/.handbrake-working"

log() {
    printf '[HandBrake AMD Watch] %s\n' "$*"
}

is_video() {
    case "${1,,}" in
        *.mkv|*.mp4|*.m4v|*.mov|*.avi|*.mpg|*.mpeg|*.ts|*.mts|*.m2ts|*.webm|*.wmv|*.flv) return 0 ;;
        *) return 1 ;;
    esac
}

wait_until_stable() {
    local file="$1"
    local previous_size=-1
    local stable_checks=0
    local size

    for _ in $(seq 1 120); do
        [[ -f "$file" ]] || return 1
        size="$(stat -c '%s' -- "$file" 2>/dev/null || printf '%s' -1)"

        if [[ "$size" == "$previous_size" && "$size" -gt 0 ]]; then
            stable_checks=$((stable_checks + 1))
        else
            previous_size="$size"
            stable_checks=0
        fi

        if (( stable_checks >= 2 )); then
            return 0
        fi
        sleep "$WATCH_SETTLE_SECONDS"
    done

    return 1
}

archive_source() {
    local source="$1"
    local destination_dir="$2"
    local base destination

    base="$(basename -- "$source")"
    destination="$destination_dir/$base"
    if [[ -e "$destination" ]]; then
        destination="$destination_dir/${base%.*}-$(date +%Y%m%d-%H%M%S)-${RANDOM}.${base##*.}"
    fi
    mv -- "$source" "$destination"
}

build_profile_args() {
    PROFILE_ARGS=()
    case "$WATCH_PROFILE" in
        rx6700-hevc10)
            PROFILE_ARGS=(--encoder vaapi_hevc --encoder-profile main10 --quality "$WATCH_QUALITY")
            ;;
        rx6700-hevc)
            PROFILE_ARGS=(--encoder vaapi_hevc --encoder-profile main --quality "$WATCH_QUALITY")
            ;;
        rx6700-h264)
            PROFILE_ARGS=(--encoder vaapi_h264 --encoder-profile high --quality "$WATCH_QUALITY")
            ;;
        handbrake-preset)
            PROFILE_ARGS=(--preset "$WATCH_HANDBRAKE_PRESET")
            ;;
        *)
            log "Unbekanntes WATCH_PROFILE: $WATCH_PROFILE"
            return 1
            ;;
    esac
}

check_vaapi_device() {
    if [[ "$WATCH_PROFILE" == "handbrake-preset" ]]; then
        return 0
    fi

    if [[ ! -e "$VAAPI_DEVICE" ]]; then
        log "WARNUNG: VAAPI_DEVICE existiert nicht: $VAAPI_DEVICE"
        log "Der Watcher bleibt aktiv; der Encode wird bei einem Job fehlschlagen und die Quelle nach /watch/error verschieben."
        return 0
    fi

    # HandBrakeCLI --help lists option syntax, not the dynamically available
    # encoder names. Do not use it to detect vaapi_hevc/vaapi_h264.
    # Probe libva instead; the actual HandBrake encoder is validated by the job.
    if vainfo --display drm --device "$VAAPI_DEVICE" 2>&1 | grep -q 'VAEntrypointEncSlice'; then
        log "VA-API Hardware-Encoding am Gerät erkannt: $VAAPI_DEVICE"
    else
        log "WARNUNG: vainfo meldet keinen VAEntrypointEncSlice für $VAAPI_DEVICE"
        log "Der Watcher bleibt aktiv; HandBrake prüft den gewählten Encoder beim ersten Job."
    fi
}

process_file() {
    local source="$1"
    local base stem final temp
    local -a args

    log "Gefunden: $source"
    if ! wait_until_stable "$source"; then
        log "Datei wurde nicht stabil oder ist verschwunden: $source"
        return 0
    fi

    base="$(basename -- "$source")"
    stem="${base%.*}"
    final="$OUTPUT_DIR/${stem}.mkv"
    if [[ -e "$final" ]]; then
        final="$OUTPUT_DIR/${stem}-$(date +%Y%m%d-%H%M%S)-${RANDOM}.mkv"
    fi
    temp="$WORK_DIR/.${stem}.$$.${RANDOM}.mkv"

    if ! build_profile_args; then
        archive_source "$source" "$ERROR_DIR"
        return 0
    fi

    args=(
        -i "$source"
        -o "$temp"
        -f av_mkv
        --markers
        --keep-metadata
        --all-audio
        --aencoder copy
        --audio-copy-mask aac,ac3,eac3,truehd,dts,dtshd,mp2,mp3,opus,flac
        --audio-fallback av_aac
        --all-subtitles
    )
    args+=("${PROFILE_ARGS[@]}")

    log "Starte Encode: Profil=$WATCH_PROFILE Qualität=$WATCH_QUALITY"
    log "Ziel: $final"

    if LIBVA_DRIVER_NAME="$LIBVA_DRIVER_NAME" VAAPI_DEVICE="$VAAPI_DEVICE" \
        HandBrakeCLI "${args[@]}"; then
        if [[ -s "$temp" ]]; then
            mv -- "$temp" "$final"
            archive_source "$source" "$DONE_DIR"
            log "Fertig: $final"
        else
            log "HandBrake meldete Erfolg, aber die Ausgabedatei ist leer."
            rm -f -- "$temp"
            archive_source "$source" "$ERROR_DIR"
        fi
    else
        log "Encode fehlgeschlagen: $source"
        rm -f -- "$temp"
        archive_source "$source" "$ERROR_DIR"
    fi
}

mkdir -p "$WATCH_DIR" "$OUTPUT_DIR" "$DONE_DIR" "$ERROR_DIR" "$WORK_DIR"
check_vaapi_device

log "Watcher aktiv: $WATCH_DIR"
log "Standardprofil: $WATCH_PROFILE"
log "Ausgabe: $OUTPUT_DIR"
log "Erfolg -> $DONE_DIR | Fehler -> $ERROR_DIR"
log "Es wird immer nur eine Datei gleichzeitig verarbeitet."

while true; do
    candidate=""
    while IFS= read -r -d '' path; do
        if is_video "$path"; then
            candidate="$path"
            break
        fi
    done < <(find "$WATCH_DIR" -mindepth 1 -maxdepth 1 -type f -print0 | sort -z)

    if [[ -n "$candidate" ]]; then
        process_file "$candidate"
    else
        sleep "$WATCH_POLL_SECONDS"
    fi
done
