#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/clients/apps/web"
OUTPUT_DIR="$WEB_DIR/build"

cd "$WEB_DIR"
npm run dist:oss:selfhost

if [[ ! -f "$OUTPUT_DIR/index.html" ]]; then
  echo "Expected Web Vault build output at $OUTPUT_DIR/index.html" >&2
  exit 1
fi

find "$OUTPUT_DIR" -type f -name "*.map" -delete

echo "Web Vault assets ready: $OUTPUT_DIR"
