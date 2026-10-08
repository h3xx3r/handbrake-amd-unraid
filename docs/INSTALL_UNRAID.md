# Installation auf Unraid

## Voraussetzungen

- Unraid 7.x
- AMD-GPU vom Host erkannt
- `/dev/dri` vorhanden
- für dieses Projekt vorgesehen: Radeon RX 6700 / RDNA2 / Navi 22

Prüfen:

```bash
ls -la /dev/dri
```

Typisch sind `card0` und `renderD128`.

## Automatische Installation

```bash
curl -fsSL https://raw.githubusercontent.com/h3xx3r/handbrake-amd-unraid/main/scripts/install-unraid.sh \
  -o /tmp/install-handbrake-amd.sh
bash /tmp/install-handbrake-amd.sh
```

Das Script:

- prüft Docker und `/dev/dri`
- erkennt standardmäßig `/dev/dri/renderD128`
- zieht `ghcr.io/h3xx3r/handbrake-amd-unraid:latest`
- erstellt `/config`, `/output` und `/watch`
- setzt die Unraid-DockerMan-Labels
- speichert ein User-Template unter `/boot/config/plugins/dockerMan/templates-user`
- startet Web-GUI, VNC und den Watch-Folder

Damit bleibt ein per Script erzeugter Container anschließend in Unraid unter **Docker -> Bearbeiten** konfigurierbar.

## Standardwerte

```text
CONTAINER_NAME          HandBrake-AMD-GUI
CONFIG_PATH             /mnt/user/appdata/handbrake-amd
STORAGE_PATH            /mnt/user
OUTPUT_PATH             /mnt/user/Media/HandBrake
WATCH_PATH              /mnt/user/Media/HandBrake/watch
WEB_PORT                5800
VNC_PORT                5901
LIBVA_DRIVER_NAME       radeonsi
VAAPI_DEVICE            automatisch /dev/dri/renderD128
WATCH_ENABLED           1
WATCH_PROFILE           gui-default
WATCH_QUALITY           24
WATCH_HANDBRAKE_PRESET  leer
WATCH_POLL_SECONDS      5
WATCH_SETTLE_SECONDS    3
TZ                      Europe/Berlin
USER_ID                 99
GROUP_ID                100
UMASK                   0022
```

## Watch-Folder

Dateien direkt im Watch-Verzeichnis werden automatisch nacheinander verarbeitet:

```text
/watch
```

Standardablauf:

1. Datei wird erkannt.
2. Der Watcher wartet, bis die Dateigröße stabil ist.
3. Der Watcher liest das in HandBrake als Standard markierte GUI-Preset aus `presets.json`.
4. HandBrakeCLI importiert genau diese Preset-Datei und verwendet den gespeicherten Preset-Namen.
5. Die fertige Datei wird nach `/output` geschrieben.
6. Erfolgreiche Quelle -> `/watch/done`.
7. Fehlgeschlagene Quelle -> `/watch/error`.

Es wird immer nur **ein automatischer Job gleichzeitig** verarbeitet.

### Empfohlen: GUI-Standardpreset

```text
WATCH_PROFILE=gui-default
```

HandBrake GTK speichert eigene Presets unter dem persistenten `/config`-Pfad. Der Watcher sucht automatisch nach `ghb/presets.json` und nimmt das Preset mit der `Default`-Markierung.

Damit übernimmt der Watcher die Einstellungen, die bereits in der GUI funktionieren, einschließlich:

- VA-API-Encoder
- Videoqualität oder Bitrate
- Profil/Level
- Audio
- Untertitel
- Filter
- Framerate und Auflösung
- MP4/MKV/WebM-Ausgabecontainer

Im Modus `gui-default` werden diese Werte nicht durch zusätzliche Watcher-Optionen überschrieben.

### Bestimmtes eigenes GUI-Preset

```bash
WATCH_PROFILE=gui-preset \
WATCH_HANDBRAKE_PRESET='Mein Preset' \
bash /tmp/install-handbrake-amd.sh
```

Der Preset-Name muss exakt der Bezeichnung in der HandBrake-GUI entsprechen.

### Weitere Watch-Profile

```text
gui-default        Standard-Preset der HandBrake-GUI (empfohlen)
gui-preset         benanntes eigenes GUI-Preset
handbrake-preset   eingebautes HandBrake-Preset
rx6700-hevc10      manuell vaapi_hevc + Main10 (experimentell)
rx6700-hevc        manuell vaapi_hevc + Main
rx6700-h264        manuell vaapi_h264 + High
```

Beispiel eingebautes HandBrake-Preset:

```bash
WATCH_PROFILE=handbrake-preset \
WATCH_HANDBRAKE_PRESET='Fast 1080p30' \
bash /tmp/install-handbrake-amd.sh
```

Watcher deaktivieren:

```bash
WATCH_ENABLED=0 bash /tmp/install-handbrake-amd.sh
```

Unterstützte Quelldateien umfassen MKV, MP4/M4V, MOV, AVI, MPG/MPEG, TS/MTS/M2TS, WEBM, WMV und FLV.

## Andere Pfade und Ports

```bash
OUTPUT_PATH=/mnt/user/Filme/HandBrake \
WATCH_PATH=/mnt/user/Filme/HandBrake/watch \
WEB_PORT=5801 \
VNC_PORT=5902 \
bash /tmp/install-handbrake-amd.sh
```

Der VNC-Containerport bleibt immer `5900`; `VNC_PORT` ist der frei wählbare Host-Port.

## VNC-Passwort

```bash
VNC_PASSWORD='mein-passwort' bash /tmp/install-handbrake-amd.sh
```

## Zweiten Render-Node verwenden

```bash
VAAPI_DEVICE=/dev/dri/renderD129 bash /tmp/install-handbrake-amd.sh
```

## Container aktualisieren

Installer erneut laden und ausführen:

```bash
curl -fsSL https://raw.githubusercontent.com/h3xx3r/handbrake-amd-unraid/main/scripts/install-unraid.sh \
  -o /tmp/install-handbrake-amd.sh
bash /tmp/install-handbrake-amd.sh
```

Persistente Daten und die in der HandBrake-GUI gespeicherten Presets bleiben unter `/config` erhalten.

## Installation über die Unraid Docker-GUI

Das Repository enthält `unraid-template.xml`. Wichtige Zuordnungen:

```text
/dev/dri  -> /dev/dri
/config   -> /mnt/user/appdata/handbrake-amd
/storage  -> /mnt/user
/output   -> /mnt/user/Media/HandBrake
/watch    -> /mnt/user/Media/HandBrake/watch
```

Für den Watcher sollte stehen:

```text
WATCH_PROFILE = gui-default
```

Web-GUI:

```text
http://UNRAID-IP:5800
```

Direktes VNC standardmäßig auf Host-Port `5901`.

## GPU testen

```bash
docker exec -it HandBrake-AMD-GUI sh -lc \
  'vainfo --display drm --device "$VAAPI_DEVICE"'
```

Für die RX 6700 sind H.264 und HEVC/H.265 die relevanten Hardware-Encoder; AV1-Hardware-Encoding gehört nicht zu RDNA2.
