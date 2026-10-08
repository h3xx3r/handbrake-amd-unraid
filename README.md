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
- Erfolg nach `/watch/done`, Fehler nach `/watch/error`
- Ausgabe nach `/output`
- RX-6700-Standardprofil: **H.265/HEVC VAAPI Main10**, Qualität `24`
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

Standardprofil:

```text
WATCH_PROFILE=rx6700-hevc10
WATCH_QUALITY=24
```

Das verwendet `vaapi_hevc` mit HEVC Main10 auf der RX 6700. Nach Erfolg wird die Quelle nach `watch/done` verschoben; bei einem Fehler nach `watch/error`. Die fertige MKV-Datei landet unter `/output`.

Unterstützte Profile:

```text
rx6700-hevc10    H.265/HEVC VAAPI Main10 (Standard)
rx6700-hevc      H.265/HEVC VAAPI Main
rx6700-h264      H.264 VAAPI High
handbrake-preset eingebautes HandBrake-Preset verwenden
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
```

Bei einer zweiten GPU kann `VAAPI_DEVICE` z. B. `/dev/dri/renderD129` sein.

## Installationsskript konfigurieren

Beispiel:

```bash
OUTPUT_PATH=/mnt/user/Filme/HandBrake \
WATCH_PATH=/mnt/user/Filme/HandBrake/watch \
WATCH_PROFILE=rx6700-h264 \
VNC_PORT=5902 \
bash /tmp/install-handbrake-amd.sh
```

Weitere Variablen stehen in [`.env.example`](.env.example).

## GPU prüfen

```bash
docker exec -it HandBrake-AMD-GUI sh -lc \
  'vainfo --display drm --device "$VAAPI_DEVICE"'
```

HandBrake VA-API prüfen:

```bash
docker exec -it HandBrake-AMD-GUI sh -lc \
  'HandBrakeCLI --help | grep -i -E "vaapi|va-api"'
```

## RX 6700

Die RX 6700 kann über Mesa/VA-API H.264 und HEVC/H.265 hardwarebeschleunigt encodieren. AV1 wird von dieser Generation hardwarebeschleunigt decodiert, aber nicht encodiert.

## HandBrake-Zweig

Die aktuelle stabile HandBrake-Version ist 1.11.2. Der native VA-API-Pfad befindet sich im Entwicklungszweig; deshalb baut dieses Image standardmäßig `master` mit:

```text
--enable-vaapi
```

Der Host stellt nur `/dev/dri` bereit; Mesa/libva liegen im Container.

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
