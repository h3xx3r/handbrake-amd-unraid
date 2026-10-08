# HandBrake AMD GUI for Unraid

HandBrake mit GTK-Oberfläche im Browser/VNC, AMD-GPU-Hardware-Encoding über Mesa VA-API und automatischem Watch-Folder. Ausgelegt für **Unraid 7.x** und insbesondere **AMD Radeon RX 6700 / RDNA2**.

## Features

- HandBrake GTK GUI im Browser über noVNC (`5800`)
- optionaler direkter VNC-Zugriff, standardmäßig Host `5901` -> Container `5900`
- AMD-GPU-Passthrough über `/dev/dri`
- Mesa `radeonsi` + VA-API
- automatische `/dev/dri`-Gruppenrechte
- persistente Konfiguration unter `/config`
- automatischer Watch-Folder mit nur einem Encode gleichzeitig
- Standardmodus übernimmt das in der HandBrake-GUI als **Standard** markierte Preset
- Erfolg nach `/watch/done`, Fehler nach `/watch/error`
- Ausgabe nach `/output`
- Unraid XML Template und editierbare DockerMan-Konfiguration
- Docker Compose
- GitHub Actions -> GHCR
- deutsche Locale und `Europe/Berlin` als Defaults

## Schnellinstallation auf Unraid

```bash
curl -fsSL https://raw.githubusercontent.com/h3xx3r/handbrake-amd-unraid/main/scripts/install-unraid.sh \
  -o /tmp/install-handbrake-amd.sh
bash /tmp/install-handbrake-amd.sh
```

Der Installer prüft Docker und `/dev/dri`, zieht `ghcr.io/h3xx3r/handbrake-amd-unraid:latest`, legt die persistenten Verzeichnisse an, startet den Container und erzeugt unter Unraid ein User-Template. Dadurch bleibt der Container anschließend über **Docker -> Bearbeiten** verwaltbar.

Web-GUI:

```text
http://UNRAID-IP:5800
```

VNC standardmäßig:

```text
UNRAID-IP:5901
```

## Automatischer Watch-Folder

Standardmäßig ist der Watcher aktiviert. Lege eine Videodatei direkt in:

```text
/mnt/user/Media/HandBrake/watch
```

Der Container wartet, bis sich die Dateigröße nicht mehr ändert, und startet dann automatisch HandBrakeCLI. Es läuft immer nur **eine Datei gleichzeitig**.

### Standard: dein HandBrake-GUI-Preset

Der Default ist jetzt:

```text
WATCH_PROFILE=gui-default
```

Dabei sucht der Watcher die von der GTK-GUI gespeicherte `presets.json` unter `/config` und verwendet das Preset, das in HandBrake als **Standard** markiert ist. HandBrakeCLI importiert diese Preset-Datei und verwendet den exakten Preset-Namen.

Dadurch werden insbesondere übernommen:

- Videoencoder und VA-API-Einstellungen
- Qualitäts-/Bitrateneinstellungen
- Audioeinstellungen
- Untertiteleinstellungen
- Filter
- Auflösung/Framerate
- Ausgabecontainer

Der Watcher überschreibt diese Werte im `gui-default`-Modus nicht mehr mit eigenen CLI-Optionen.

Nach Erfolg wird die Quelle nach `watch/done` verschoben; bei einem echten Encode-Fehler nach `watch/error`. Die fertige Datei landet unter `/output` und erhält die zum Preset passende Endung (`.mp4`, `.mkv` oder `.webm`).

### Bestimmtes eigenes GUI-Preset verwenden

```text
WATCH_PROFILE=gui-preset
WATCH_HANDBRAKE_PRESET=Mein Presetname
```

Der Name muss exakt dem Preset-Namen in der HandBrake-GUI entsprechen.

### Weitere Profile

```text
gui-default       als Standard markiertes eigenes GUI-Preset (empfohlen)
gui-preset        eigenes GUI-Preset über WATCH_HANDBRAKE_PRESET
handbrake-preset  eingebautes HandBrake-Preset
rx6700-hevc10     manuell H.265 VAAPI Main10 (experimentell)
rx6700-hevc       manuell H.265 VAAPI Main
rx6700-h264       manuell H.264 VAAPI High
```

Für ein eingebautes HandBrake-Preset:

```text
WATCH_PROFILE=handbrake-preset
WATCH_HANDBRAKE_PRESET=Fast 1080p30
```

Watcher deaktivieren:

```text
WATCH_ENABLED=0
```

Unterstützt werden u. a. MKV, MP4/M4V, MOV, AVI, MPG/MPEG, TS/MTS/M2TS, WEBM, WMV und FLV.

## Wichtige Unraid-Einstellungen

```text
Device             /dev/dri -> /dev/dri
LIBVA_DRIVER_NAME  radeonsi
VAAPI_DEVICE       /dev/dri/renderD128
WebUI Host-Port    5800
VNC Host-Port      5901
WATCH_PROFILE      gui-default
```

Bei einer zweiten GPU kann `VAAPI_DEVICE` z. B. `/dev/dri/renderD129` sein.

## Installationsskript konfigurieren

Beispiel:

```bash
OUTPUT_PATH=/mnt/user/Filme/HandBrake \
WATCH_PATH=/mnt/user/Filme/HandBrake/watch \
WATCH_PROFILE=gui-default \
VNC_PORT=5902 \
bash /tmp/install-handbrake-amd.sh
```

Weitere Variablen stehen in [`.env.example`](.env.example).

## GPU prüfen

```bash
docker exec -it HandBrake-AMD-GUI sh -lc \
  'vainfo --display drm --device "$VAAPI_DEVICE"'
```

## RX 6700

Die RX 6700 kann über Mesa/VA-API H.264 und HEVC/H.265 hardwarebeschleunigt encodieren. AV1 wird von dieser Generation hardwarebeschleunigt decodiert, aber nicht encodiert.

## HandBrake-Zweig

Das Image baut standardmäßig den HandBrake-Entwicklungszweig `master` mit:

```text
--enable-vaapi
```

Der Host stellt `/dev/dri` bereit; Mesa/libva liegen im Container.

## Dokumentation

- [`docs/INSTALL_UNRAID.md`](docs/INSTALL_UNRAID.md)
- [`docs/RX6700.md`](docs/RX6700.md)

## Image lokal bauen

```bash
git clone https://github.com/h3xx3r/handbrake-amd-unraid.git
cd handbrake-amd-unraid
./scripts/build-unraid.sh
```

Oder:

```bash
cp .env.example .env
docker compose up -d --build
```

## GitHub Container Registry

```text
ghcr.io/h3xx3r/handbrake-amd-unraid:latest
```

Das GHCR-Paket muss öffentlich sein, wenn Unraid ohne GitHub-Login pullen soll.

## Upstream

- HandBrake: https://github.com/HandBrake/HandBrake
- HandBrake Dokumentation: https://handbrake.fr/docs/

## Lizenz

Die Dateien dieses Repositories stehen unter der MIT-Lizenz. Enthaltene Komponenten behalten ihre jeweiligen Lizenzen.
