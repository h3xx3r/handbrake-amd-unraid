# Installation auf Unraid

## Voraussetzungen

- Unraid 7.x
- AMD-GPU vom Host erkannt
- `/dev/dri` vorhanden
- Für dieses Projekt getestet/ausgelegt: Radeon RX 6700 (RDNA2 / Navi 22)

Auf dem Unraid-Terminal prüfen:

```bash
ls -la /dev/dri
```

Typisch:

```text
card0
renderD128
```

Bei mehreren GPUs kann die Radeon z. B. `renderD129` sein.

## Automatische Installation per Script

Empfohlen ist das mitgelieferte Script `scripts/install-unraid.sh`.

Auf dem Unraid-Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/h3xx3r/handbrake-amd-unraid/main/scripts/install-unraid.sh \
  -o /tmp/install-handbrake-amd.sh
bash /tmp/install-handbrake-amd.sh
```

Das Script erledigt automatisch:

- Prüfung, ob Docker läuft
- Prüfung von `/dev/dri`
- automatische Auswahl von `/dev/dri/renderD128`, sofern vorhanden
- Download von `ghcr.io/h3xx3r/handbrake-amd-unraid:latest`
- Anlage der persistenten Verzeichnisse
- Ersetzen eines bereits vorhandenen Containers gleichen Namens
- Start mit `radeonsi`, VA-API und Unraid-kompatiblen UID/GID-Defaults
- Ausgabe der Web-GUI- und VNC-Adresse

Standardwerte:

```text
CONTAINER_NAME   HandBrake-AMD-GUI
CONFIG_PATH      /mnt/user/appdata/handbrake-amd
STORAGE_PATH     /mnt/user
OUTPUT_PATH      /mnt/user/Media/HandBrake
WATCH_PATH       /mnt/user/Media/HandBrake/watch
WEB_PORT         5800
VNC_PORT         5900
LIBVA_DRIVER_NAME radeonsi
VAAPI_DEVICE     automatisch /dev/dri/renderD128
TZ               Europe/Berlin
USER_ID          99
GROUP_ID         100
UMASK            0022
```

### Andere Medienpfade verwenden

```bash
OUTPUT_PATH=/mnt/user/Filme/HandBrake \
WATCH_PATH=/mnt/user/Filme/HandBrake/watch \
bash /tmp/install-handbrake-amd.sh
```

### Anderen Web-Port verwenden

```bash
WEB_PORT=5801 bash /tmp/install-handbrake-amd.sh
```

Danach lautet die Web-GUI entsprechend:

```text
http://UNRAID-IP:5801
```

### VNC-Passwort setzen

```bash
VNC_PASSWORD='mein-passwort' bash /tmp/install-handbrake-amd.sh
```

### Zweiten Render-Node verwenden

Wenn die RX 6700 beispielsweise `renderD129` ist:

```bash
VAAPI_DEVICE=/dev/dri/renderD129 bash /tmp/install-handbrake-amd.sh
```

### Container aktualisieren

Das Installationsscript kann später erneut ausgeführt werden. Es zieht zuerst
das aktuelle `latest`-Image und ersetzt danach den bestehenden Container.
Die Daten unter `/config`, `/output`, `/watch` und `/storage` bleiben erhalten,
weil sie auf dem Unraid-Host liegen.

```bash
bash /tmp/install-handbrake-amd.sh
```

Falls die temporäre Datei nicht mehr vorhanden ist:

```bash
curl -fsSL https://raw.githubusercontent.com/h3xx3r/handbrake-amd-unraid/main/scripts/install-unraid.sh \
  -o /tmp/install-handbrake-amd.sh
bash /tmp/install-handbrake-amd.sh
```

## Installation über die Unraid Docker-GUI

1. Docker öffnen.
2. Einen neuen Container aus dem beiliegenden `unraid-template.xml` anlegen.
3. Als Repository verwenden:

```text
ghcr.io/h3xx3r/handbrake-amd-unraid:latest
```

4. Folgende Zuordnung muss vorhanden sein:

```text
Host:      /dev/dri
Container: /dev/dri
```

5. Standardpfade:

```text
/config   -> /mnt/user/appdata/handbrake-amd
/storage  -> /mnt/user
/output   -> /mnt/user/Media/HandBrake
/watch    -> /mnt/user/Media/HandBrake/watch
```

6. Container starten.
7. Web-GUI öffnen:

```text
http://UNRAID-IP:5800
```

Direktes VNC ist optional auf Port `5900` möglich.

## RX 6700 Einstellungen

Standardmäßig verwenden:

```text
LIBVA_DRIVER_NAME=radeonsi
VAAPI_DEVICE=/dev/dri/renderD128
```

Wenn die RX 6700 als `renderD129` erscheint:

```text
VAAPI_DEVICE=/dev/dri/renderD129
```

## GPU-Funktion testen

```bash
docker exec -it HandBrake-AMD-GUI sh -lc \
  'vainfo --display drm --device "$VAAPI_DEVICE"'
```

HandBrake prüfen:

```bash
docker exec -it HandBrake-AMD-GUI sh -lc \
  'HandBrakeCLI --version && HandBrakeCLI --help | grep -i -E "vaapi|va-api"'
```

## Encoder für RX 6700

Die RX 6700 (RDNA2) eignet sich für Hardware-Encoding von H.264 und HEVC/H.265.
AV1-Hardware-Encoding gehört nicht zu dieser GPU-Generation.

In HandBrake daher bevorzugt:

- H.264 VAAPI für maximale Kompatibilität
- H.265/HEVC VAAPI für bessere Kompression
- HEVC 10-bit, wenn vom aktuellen HandBrake/Mesa-Stack angeboten

## Hinweis zum HandBrake-Zweig

HandBrake 1.11.2 ist die aktuelle stabile Version zum Zeitpunkt dieser
Dokumentation. Der neue Mesa-VAAPI-Encoder befindet sich im HandBrake-
Entwicklungszweig und ist für 1.12 vorgesehen. Deshalb baut dieses Image
standardmäßig `master`.

Das vermeidet bei RDNA2 die Abhängigkeit von den alten proprietären
`amf-amdgpu-pro`-Bibliotheken. AMD hat AMF ab Radeon Software for Linux 25.20
entfernt und empfiehlt den Umstieg auf VA-API/Mesa Multimedia.

## GHCR-Paket einmalig öffentlich machen

GitHub Container Registry erstellt ein neues Paket standardmäßig privat.
Nach dem ersten erfolgreichen GitHub-Actions-Build:

1. GitHub-Profil `h3xx3r` öffnen.
2. `Packages` öffnen.
3. `handbrake-amd-unraid` öffnen.
4. `Package settings` öffnen.
5. `Change visibility` -> `Public`.

Danach kann Unraid das Image ohne GitHub-Login herunterladen.

Wenn das Paket noch privat ist, schlägt das Installationsscript beim
`docker pull` fehl und weist auf diesen Schritt hin.
