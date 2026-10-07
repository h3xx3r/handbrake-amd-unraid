# syntax=docker/dockerfile:1.7
# HandBrake GTK GUI for Unraid with browser VNC/noVNC and AMD Mesa VA-API.
# Multi-stage build: compile in clean Ubuntu, keep runtime lean and predictable.

ARG HANDBRAKE_REF=master

FROM ubuntu:24.04 AS builder
ARG HANDBRAKE_REF
ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    appstream \
    autoconf \
    automake \
    build-essential \
    ca-certificates \
    cmake \
    desktop-file-utils \
    gettext \
    git \
    gstreamer1.0-libav \
    gstreamer1.0-plugins-good \
    libass-dev \
    libbz2-dev \
    libdrm-dev \
    libfontconfig-dev \
    libfreetype-dev \
    libfribidi-dev \
    libgstreamer-plugins-base1.0-dev \
    libgtk-4-dev \
    libharfbuzz-dev \
    libjansson-dev \
    liblzma-dev \
    libmp3lame-dev \
    libnuma-dev \
    libogg-dev \
    libopus-dev \
    libsamplerate0-dev \
    libspeex-dev \
    libssl-dev \
    libtheora-dev \
    libtool \
    libtool-bin \
    libturbojpeg0-dev \
    libva-dev \
    libvorbis-dev \
    libvpx-dev \
    libx11-dev \
    libx264-dev \
    libxml2-dev \
    m4 \
    make \
    meson \
    nasm \
    ninja-build \
    patch \
    pkg-config \
    python3 \
    tar \
    xz-utils \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

RUN mkdir -p /tmp/HandBrake \
    && cd /tmp/HandBrake \
    && git init \
    && git remote add origin https://github.com/HandBrake/HandBrake.git \
    && git fetch --depth 1 origin "${HANDBRAKE_REF}" \
    && git checkout --detach FETCH_HEAD \
    && ./configure \
         --prefix=/opt/handbrake \
         --enable-vaapi \
         --launch-jobs="$(nproc)" \
         --launch \
    && make --directory=build install \
    && test -x /opt/handbrake/bin/HandBrakeCLI \
    && test -x /opt/handbrake/bin/ghb

FROM ubuntu:24.04 AS runtime
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    adwaita-icon-theme \
    ca-certificates \
    curl \
    dbus-x11 \
    desktop-file-utils \
    fonts-dejavu-core \
    gosu \
    gsettings-desktop-schemas \
    gstreamer1.0-libav \
    gstreamer1.0-plugins-good \
    hicolor-icon-theme \
    libass9 \
    libdrm-amdgpu1 \
    libdrm2 \
    libfontconfig1 \
    libfreetype6 \
    libfribidi0 \
    libgstreamer-plugins-base1.0-0 \
    libgtk-4-1 \
    libgudev-1.0-0 \
    libharfbuzz0b \
    libjansson4 \
    libmp3lame0 \
    libnuma1 \
    libogg0 \
    libopus0 \
    libsamplerate0 \
    libspeex1 \
    libtheora0 \
    libturbojpeg \
    libva-drm2 \
    libva-x11-2 \
    libva2 \
    libvorbis0a \
    libvpx9 \
    libx11-6 \
    libx264-164 \
    libxml2 \
    locales \
    mesa-va-drivers \
    novnc \
    openbox \
    shared-mime-info \
    vainfo \
    websockify \
    x11vnc \
    xvfb \
    && locale-gen de_DE.UTF-8 en_US.UTF-8 \
    && ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html \
    && groupadd --gid 1000 app \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash app \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/handbrake /opt/handbrake
COPY startapp.sh /startapp.sh

RUN chmod +x /startapp.sh \
    && mkdir -p /config /storage /output /watch \
    && ldd /opt/handbrake/bin/ghb | tee /tmp/ghb-ldd.txt \
    && ! grep -q 'not found' /tmp/ghb-ldd.txt \
    && /opt/handbrake/bin/HandBrakeCLI --version

ENV PATH="/opt/handbrake/bin:${PATH}" \
    HOME="/config" \
    XDG_CONFIG_HOME="/config/xdg/config" \
    XDG_CACHE_HOME="/config/xdg/cache" \
    XDG_DATA_HOME="/config/xdg/data" \
    DISPLAY=":0" \
    DISPLAY_WIDTH="1920" \
    DISPLAY_HEIGHT="1080" \
    DISPLAY_DEPTH="24" \
    TZ="Europe/Berlin" \
    LANG="de_DE.UTF-8" \
    LC_ALL="de_DE.UTF-8" \
    LIBVA_DRIVER_NAME="radeonsi" \
    VAAPI_DEVICE="/dev/dri/renderD128" \
    USER_ID="99" \
    GROUP_ID="100" \
    UMASK="0022" \
    KEEP_APP_RUNNING="1" \
    VNC_PASSWORD=""

VOLUME ["/config", "/storage", "/output", "/watch"]
EXPOSE 5800 5900
WORKDIR /storage

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:5800/ >/dev/null || exit 1

ENTRYPOINT ["/startapp.sh"]

LABEL org.opencontainers.image.title="HandBrake AMD GUI for Unraid" \
      org.opencontainers.image.description="HandBrake GTK over noVNC/VNC with AMD Mesa VA-API support for Unraid" \
      org.opencontainers.image.source="https://github.com/h3xx3r/handbrake-amd-unraid" \
      org.opencontainers.image.licenses="MIT"
