#!/bin/bash
set -e

echo "=== Host /dev/dri ==="
ls -la /dev/dri || true

echo
echo "=== Container VA-API ==="
docker exec handbrake-amd sh -lc '
  echo "LIBVA_DRIVER_NAME=$LIBVA_DRIVER_NAME"
  echo "VAAPI_DEVICE=$VAAPI_DEVICE"
  vainfo --display drm --device "${VAAPI_DEVICE:-/dev/dri/renderD128}" || true
'

echo
echo "=== HandBrake encoders ==="
docker exec handbrake-amd sh -lc '
  HandBrakeCLI --version
  HandBrakeCLI --help 2>&1 | grep -i -E "vaapi|va-api|vcn|amf" || true
'
