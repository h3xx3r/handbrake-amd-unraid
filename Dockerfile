# syntax=docker/dockerfile:1.7
# HandBrake GTK GUI for Unraid with browser VNC/noVNC and AMD Mesa VA-API.
# RX 6700 / RDNA2 friendly: no proprietary AMD host driver required.

ARG GUI_BASE=jlesage/baseimage-gui:ubuntu-24.04-v4
FROM ${GUI_BASE}

USER 0:0

ARG DEBIAN_FRONTEND=noninteractive
ARG HANDBRAKE_REF=master

# Dependencies follow the current HandBrake Ubuntu build documentation,
# plus Mesa/libva runtime components required for AMD VA-API in the container.
RUN apt-get update && apt-get install -y --no-install-recommends \
    appstream \
    autoconf \
    automake \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    desktop-file-utils \
    gettext \
    git \
    gstreamer1.0-libav \
    gstreamer1.0-plugins-good \
    libass-dev \
    libbz2-dev \
    libdrm-amdgpu1 \
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
    libva-drm2 \
    libva-x11-2 \
    libvorbis-dev \
    libvpx-dev \
    libx11-dev \
    libx264-dev \
    libxml2-dev \
    locales \
    m4 \
    make \
    mesa-va-drivers \
    mesa-utils \
    meson \
    nasm \
    ninja-build \
    patch \
    pkg-config \
    vainfo \
    zlib1g-dev \
    && locale-gen de_DE.UTF-8 en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# Fetch a branch, tag, or commit and build HandBrake with VA-API support.
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
    && rm -rf /tmp/HandBrake

COPY startapp.sh /startapp.sh
COPY rootfs/ /

RUN chmod +x /startapp.sh \
    /etc/cont-env.d/SUP_GROUP_IDS_INTERNAL_GPU \
    && mkdir -p /storage /output /watch /config \
    && set-cont-env APP_NAME "HandBrake AMD" \
    && set-cont-env TAKE_CONFIG_OWNERSHIP "1"

ENV PATH="/opt/handbrake/bin:${PATH}" \
    HOME="/config" \
    XDG_CONFIG_HOME="/config/xdg/config" \
    XDG_CACHE_HOME="/config/xdg/cache" \
    XDG_DATA_HOME="/config/xdg/data" \
    TZ="Europe/Berlin" \
    LANG="de_DE.UTF-8" \
    LC_ALL="de_DE.UTF-8" \
    LIBVA_DRIVER_NAME="radeonsi" \
    VAAPI_DEVICE="/dev/dri/renderD128" \
    USER_ID="99" \
    GROUP_ID="100" \
    UMASK="0022" \
    KEEP_APP_RUNNING="1"

VOLUME ["/config", "/storage", "/output", "/watch"]
EXPOSE 5800 5900
WORKDIR /storage

LABEL org.opencontainers.image.title="HandBrake AMD GUI for Unraid" \
      org.opencontainers.image.description="HandBrake GTK over noVNC/VNC with AMD Mesa VA-API support for Unraid" \
      org.opencontainers.image.source="https://github.com/h3xx3r/handbrake-amd-unraid" \
      org.opencontainers.image.licenses="MIT"
