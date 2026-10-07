# HandBrake AMD GUI for Unraid

HandBrake mit vollständiger GTK-Oberfläche im Browser/VNC und AMD-GPU-
Hardware-Encoding über Mesa VA-API. Das Projekt ist für **Unraid 7.x** und
insbesondere auch für **AMD Radeon RX 6700 / RDNA2** ausgelegt.

## Features

- HandBrake GTK GUI
- Browser-GUI über noVNC auf Port `5800`
- optionaler direkter VNC-Zugriff auf Port `5900`
- AMD-GPU-Passthrough über `/dev/dri`
- Mesa `radeonsi` + VA-API
- keine Installation eines proprietären AMD-Treibers auf Unraid nötig
- automatische Erkennung der `/dev/dri`-Gruppenrechte
- persistente HandBrake-Konfiguration unter `/config`
- Quell-, Ausgabe- und Watch-Verzeichnisse
- Unraid XML Template
- Docker Compose
- automatischer GitHub-Actions-Build nach GHCR
- Installationsskript für Unraid
- deutsche Locale und `Europe/Berlin` als Defaults

## Schnellinstallation auf Unraid

### Installationsskript (empfohlen)

Auf dem Unraid-Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/h3xx3r/handbrake-amd-unraid/main/scripts/install-unraid.sh \
  -o /tmp/install-handbrake-amd.sh
bash /tmp/install-handbrake-amd.sh
```

Das Skript prüft Docker und `/dev/dri`, erkennt standardmäßig `renderD128`,
lädt das fertige GHCR-Image, legt die persistenten Verzeichnisse an und
startet den Container mit den passenden AMD-VAAPI-Defaults.

Eigene Pfade oder Ports können direkt als Umgebungsvariablen gesetzt werden:

```bash
OUTPUT_PATH=/mnt/user/Filme/HandBrake \
WEB_PORT=5801 \
VNC_PASSWORD='mein-passwort' \
bash /tmp/install-handbrake-amd.sh
```

Nach erfolgreicher Installation ist die GUI standardmäßig erreichbar unter:

```text
http://UNRAID-IP:5800
```

### Manuelle Installation

Nach dem ersten erfolgreichen GHCR-Build lautet das Image:

```text
ghcr.io/h3xx3r/handbrake-amd-unraid:latest
```

Wichtige Einstellung:

```text
Device: /dev/dri -> /dev/dri
```

Standardwerte für AMD:

```text
LIBVA_DRIVER_NAME=radeonsi
VAAPI_DEVICE=/dev/dri/renderD128
```

Die vollständige Schritt-für-Schritt-Anleitung steht unter:

- [`docs/INSTALL_UNRAID.md`](docs/INSTALL_UNRAID.md)
- [`docs/RX6700.md`](docs/RX6700.md)

## Warum der HandBrake-Entwicklungszweig?

Die stabile HandBrake-Version 1.11.2 unterstützt AMD VCN unter Linux über
AMF. Für RDNA2 benötigen die offiziellen HandBrake-Hinweise dabei ältere
`amf-amdgpu-pro`-Bibliotheken. AMD liefert AMF seit Radeon Software for Linux
25.20 nicht mehr aus und empfiehlt VA-API / Mesa Multimedia als Nachfolger.

HandBrake entwickelt deshalb einen nativen VA-API-Pfad; die entsprechenden
Änderungen befinden sich aktuell im Entwicklungszweig und sind für 1.12
vorgesehen. Dieses Image baut standardmäßig `master` mit:

```text
--enable-vaapi
```

Das ist für einen Unraid-Container deutlich sauberer: Der Host stellt nur
`/dev/dri` bereit, während Mesa/libva im Container liegen.

> Hinweis: Da dieser VA-API-Pfad noch Entwicklungsstand ist, kann es mit
> einzelnen Kombinationen aus HandBrake, Mesa, Codec und Containerformat
> noch Probleme geben. Bei Problemen mit MP4 zunächst MKV testen.

## RX 6700

Für die RX 6700 sind H.264 und H.265/HEVC die relevanten Hardware-Encoder.
Die Karte besitzt kein AV1-Hardware-Encoding.

Empfehlung:

- H.264 VAAPI: maximale Abspiel-Kompatibilität
- H.265/HEVC VAAPI: bessere Kompression
- H.265 10-bit: verwenden, wenn im aktuellen Build angeboten

## Installationsskript konfigurieren

Das Skript `scripts/install-unraid.sh` unterstützt unter anderem:

```text
IMAGE            ghcr.io/h3xx3r/handbrake-amd-unraid:latest
CONTAINER_NAME   HandBrake-AMD-GUI
CONFIG_PATH      /mnt/user/appdata/handbrake-amd
STORAGE_PATH     /mnt/user
OUTPUT_PATH      /mnt/user/Media/HandBrake
WATCH_PATH       /mnt/user/Media/HandBrake/watch
WEB_PORT         5800
VNC_PORT         5900
VAAPI_DEVICE     automatisch /dev/dri/renderD128
LIBVA_DRIVER_NAME radeonsi
VNC_PASSWORD     leer
TZ               Europe/Berlin
USER_ID          99
GROUP_ID         100
UMASK            0022
```

Beispiel bei einer zweiten GPU:

```bash
VAAPI_DEVICE=/dev/dri/renderD129 bash /tmp/install-handbrake-amd.sh
```

Das Skript kann erneut ausgeführt werden, um den vorhandenen Container durch
das aktuell gepullte Image zu ersetzen. Die Daten unter `/config` und den
gemounteten Medienpfaden bleiben erhalten.

## Image lokal bauen

```bash
git clone https://github.com/h3xx3r/handbrake-amd-unraid.git
cd handbrake-amd-unraid
chmod +x scripts/*.sh startapp.sh rootfs/etc/cont-env.d/SUP_GROUP_IDS_INTERNAL_GPU
./scripts/build-unraid.sh
```

Alternativ:

```bash
cp .env.example .env
docker compose up -d --build
```

## Einen bestimmten HandBrake-Stand bauen

Branch:

```bash
HANDBRAKE_REF=master ./scripts/build-unraid.sh
```

Tag oder Commit:

```bash
HANDBRAKE_REF=<tag-oder-commit> ./scripts/build-unraid.sh
```

## GPU prüfen

```bash
./scripts/test-amd-vaapi.sh
```

oder:

```bash
docker exec -it HandBrake-AMD-GUI sh
vainfo --display drm --device /dev/dri/renderD128
HandBrakeCLI --help | grep -i -E 'vaapi|va-api'
```

## GitHub Container Registry

Der Workflow `.github/workflows/docker-publish.yml` baut bei Änderungen am
Docker-Stack automatisch:

```text
ghcr.io/h3xx3r/handbrake-amd-unraid:latest
```

Neue GHCR-Pakete sind zunächst privat. Nach dem ersten Build muss das Paket
in GitHub einmalig auf **Public** gestellt werden, damit Unraid ohne Login
pullen kann. Details: [`docs/INSTALL_UNRAID.md`](docs/INSTALL_UNRAID.md).

## Upstream

- HandBrake: https://github.com/HandBrake/HandBrake
- HandBrake Dokumentation: https://handbrake.fr/docs/
- jlesage baseimage-gui: https://github.com/jlesage/docker-baseimage-gui

## Lizenz

Die Dateien dieses Repositories stehen unter der MIT-Lizenz. HandBrake,
Mesa, jlesage/baseimage-gui und weitere enthaltene Komponenten behalten ihre
jeweiligen eigenen Lizenzen.
