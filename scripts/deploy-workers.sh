#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKERS_DIR="$ROOT_DIR/workers"

echo "Checking Workers TypeScript..."
cd "$WORKERS_DIR"
npm run typecheck

echo "Running Workers tests..."
npm run test

echo "Building Web Vault static assets..."
cd "$ROOT_DIR"
"$ROOT_DIR/scripts/build-workers-web-assets.sh"

echo "Deploying Cloudflare Worker..."
cd "$WORKERS_DIR"
npx wrangler deploy "$@"
