#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

"${SCRIPT_DIR}/build.sh"

cd "${ROOT_DIR}"
rm -f KeepLid-v1.0.0-macos-arm64.zip
zip -r -y KeepLid-v1.0.0-macos-arm64.zip KeepLid.app .build/release/keeplid
echo "==> Packaged KeepLid-v1.0.0-macos-arm64.zip"
