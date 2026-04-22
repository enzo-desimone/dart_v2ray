#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${ROOT_DIR}/build"
GO_VERSION="1.23.6"

if ! command -v go >/dev/null 2>&1; then
  echo "error: go not found. Install Go ${GO_VERSION}." >&2
  exit 1
fi

mkdir -p "${OUT_DIR}/darwin_arm64" "${OUT_DIR}/darwin_amd64" "${OUT_DIR}/universal"

pushd "${ROOT_DIR}" >/dev/null

go mod tidy

for ARCH in arm64 amd64; do
  TARGET_DIR="${OUT_DIR}/darwin_${ARCH}"
  echo "Building libxraybridge for darwin/${ARCH}"
  CGO_ENABLED=1 GOOS=darwin GOARCH="${ARCH}" \
    go build -trimpath -buildvcs=false -buildmode=c-archive \
    -o "${TARGET_DIR}/libxraybridge.a" ./bridge.go

  cp -f "${TARGET_DIR}/libxraybridge.h" "${TARGET_DIR}/libxraybridge.generated.h"
  cp -f "${ROOT_DIR}/include/libxraybridge.h" "${TARGET_DIR}/libxraybridge.h"
done

lipo -create \
  "${OUT_DIR}/darwin_arm64/libxraybridge.a" \
  "${OUT_DIR}/darwin_amd64/libxraybridge.a" \
  -output "${OUT_DIR}/universal/libxraybridge.a"

cp -f "${ROOT_DIR}/include/libxraybridge.h" "${OUT_DIR}/universal/libxraybridge.h"

echo "Built universal archive: ${OUT_DIR}/universal/libxraybridge.a"
echo "Header: ${OUT_DIR}/universal/libxraybridge.h"

popd >/dev/null
