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

echo "Rendering production Wrangler config..."
cd "$WORKERS_DIR"
WRANGLER_CONFIG_OUT="${WRANGLER_CONFIG_OUT:-wrangler.deploy.toml}" npm run render:wrangler -- --strict

echo "Deploying Cloudflare Worker..."
npx wrangler deploy --config "$WRANGLER_CONFIG_OUT" "$@"
