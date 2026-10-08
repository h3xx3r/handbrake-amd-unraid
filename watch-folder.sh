#!/usr/bin/env bash
set -Eeuo pipefail

WATCH_DIR="${WATCH_DIR:-/watch}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
WATCH_PROFILE="${WATCH_PROFILE:-gui-default}"
WATCH_QUALITY="${WATCH_QUALITY:-24}"
WATCH_POLL_SECONDS="${WATCH_POLL_SECONDS:-5}"
WATCH_SETTLE_SECONDS="${WATCH_SETTLE_SECONDS:-3}"
WATCH_HANDBRAKE_PRESET="${WATCH_HANDBRAKE_PRESET:-}"
WATCH_PRESET_FILE="${WATCH_PRESET_FILE:-}"
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

find_gui_preset_file() {
    local candidate

    if [[ -n "$WATCH_PRESET_FILE" && -f "$WATCH_PRESET_FILE" ]]; then
        printf '%s\n' "$WATCH_PRESET_FILE"
        return 0
    fi

    for candidate in \
        /config/xdg/config/ghb/presets.json \
        /config/.config/ghb/presets.json \
        /config/ghb/presets.json
    do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    candidate="$(find /config -maxdepth 6 -type f -path '*/ghb/presets.json' -print -quit 2>/dev/null || true)"
    [[ -n "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
}

format_to_extension() {
    case "$1" in
        av_mp4|mp4|m4v) printf 'mp4' ;;
        av_webm|webm) printf 'webm' ;;
        av_mkv|mkv|matroska|*) printf 'mkv' ;;
    esac
}

resolve_gui_preset() {
    PRESET_FILE="$(find_gui_preset_file || true)"
    if [[ -z "$PRESET_FILE" ]]; then
        log "Kein HandBrake-GUI-Preset gefunden. Erwartet wird normalerweise /config/xdg/config/ghb/presets.json"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        log "jq fehlt im Container; GUI-Preset kann nicht ausgewertet werden."
        return 1
    fi

    case "$WATCH_PROFILE" in
        gui-default)
            PRESET_NAME="$(jq -r '.. | objects | select(((.Folder? // false) == false) and (.Default? == true)) | .PresetName? // empty' "$PRESET_FILE" | head -n 1)"
            if [[ -z "$PRESET_NAME" ]]; then
                PRESET_NAME="$(jq -r '.. | objects | select(((.Folder? // false) == false) and (.PresetName? != null) and ((.Type? // 0) != 0)) | .PresetName' "$PRESET_FILE" | head -n 1)"
                [[ -n "$PRESET_NAME" ]] && log "Kein Default-Marker gefunden; verwende erstes eigenes Preset: $PRESET_NAME"
            fi
            ;;
        gui-preset)
            PRESET_NAME="$WATCH_HANDBRAKE_PRESET"
            ;;
        *)
            return 1
            ;;
    esac

    if [[ -z "$PRESET_NAME" ]]; then
        log "Kein passendes GUI-Preset gefunden. Öffne HandBrake und markiere dein gewünschtes Preset als Standard."
        return 1
    fi

    if ! jq -e --arg name "$PRESET_NAME" '.. | objects | select(((.Folder? // false) == false) and (.PresetName? == $name))' "$PRESET_FILE" >/dev/null; then
        log "Preset '$PRESET_NAME' wurde in $PRESET_FILE nicht gefunden."
        return 1
    fi

    PRESET_FORMAT="$(jq -r --arg name "$PRESET_NAME" '.. | objects | select(((.Folder? // false) == false) and (.PresetName? == $name)) | .FileFormat? // empty' "$PRESET_FILE" | head -n 1)"
    OUTPUT_EXTENSION="$(format_to_extension "$PRESET_FORMAT")"
    PROFILE_ARGS=(--preset-import-file "$PRESET_FILE" --preset "$PRESET_NAME")
    log "Verwende HandBrake-GUI-Preset: $PRESET_NAME ($PRESET_FILE)"
}

build_profile_args() {
    PROFILE_ARGS=()
    OUTPUT_EXTENSION="mkv"

    case "$WATCH_PROFILE" in
        gui-default|gui-preset)
            resolve_gui_preset
            ;;
        handbrake-preset)
            [[ -n "$WATCH_HANDBRAKE_PRESET" ]] || {
                log "WATCH_HANDBRAKE_PRESET ist leer."
                return 1
            }
            OUTPUT_EXTENSION="mp4"
            PROFILE_ARGS=(--preset "$WATCH_HANDBRAKE_PRESET")
            ;;
        rx6700-hevc10)
            PROFILE_ARGS=(--encoder vaapi_hevc --encoder-profile main10 --quality "$WATCH_QUALITY")
            ;;
        rx6700-hevc)
            PROFILE_ARGS=(--encoder vaapi_hevc --encoder-profile main --quality "$WATCH_QUALITY")
            ;;
        rx6700-h264)
            PROFILE_ARGS=(--encoder vaapi_h264 --encoder-profile high --quality "$WATCH_QUALITY")
            ;;
        *)
            log "Unbekanntes WATCH_PROFILE: $WATCH_PROFILE"
            return 1
            ;;
    esac
}

check_vaapi_device() {
    if [[ ! -e "$VAAPI_DEVICE" ]]; then
        log "WARNUNG: VAAPI_DEVICE existiert nicht: $VAAPI_DEVICE"
        return 0
    fi

    if vainfo --display drm --device "$VAAPI_DEVICE" 2>&1 | grep -q 'VAEntrypointEncSlice'; then
        log "VA-API Hardware-Encoding am Gerät erkannt: $VAAPI_DEVICE"
    else
        log "WARNUNG: vainfo meldet keinen VAEntrypointEncSlice für $VAAPI_DEVICE"
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

    if ! build_profile_args; then
        log "Profil ist momentan nicht verfügbar. Quelle bleibt im Watch-Ordner und wird später erneut versucht."
        sleep "$WATCH_POLL_SECONDS"
        return 0
    fi

    base="$(basename -- "$source")"
    stem="${base%.*}"
    final="$OUTPUT_DIR/${stem}.${OUTPUT_EXTENSION}"
    if [[ -e "$final" ]]; then
        final="$OUTPUT_DIR/${stem}-$(date +%Y%m%d-%H%M%S)-${RANDOM}.${OUTPUT_EXTENSION}"
    fi
    temp="$WORK_DIR/.${stem}.$$.${RANDOM}.${OUTPUT_EXTENSION}"

    args=(
        -i "$source"
        -o "$temp"
    )
    args+=("${PROFILE_ARGS[@]}")

    log "Starte Encode: WATCH_PROFILE=$WATCH_PROFILE"
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
log "Watch-Profilmodus: $WATCH_PROFILE"
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
