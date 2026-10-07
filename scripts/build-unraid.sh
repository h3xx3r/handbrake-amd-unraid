#!/bin/bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-handbrake-amd-gui:latest}"
HANDBRAKE_REF="${HANDBRAKE_REF:-master}"

echo "Building ${IMAGE_NAME}"
echo "HandBrake ref: ${HANDBRAKE_REF}"

docker build \
  --build-arg HANDBRAKE_REF="${HANDBRAKE_REF}" \
  -t "${IMAGE_NAME}" \
  .

echo
echo "Build finished: ${IMAGE_NAME}"
echo "Now add the supplied Unraid template or run docker compose up -d."
