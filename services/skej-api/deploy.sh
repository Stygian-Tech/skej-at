#!/usr/bin/env bash
# Deploy the Skej gateway from services/skej-api using its local fly.toml.
#
# Usage: bash services/skej-api/deploy.sh dev|main
set -euo pipefail

SERVICE_DIR="$(cd "$(dirname "$0")" && pwd)"
BRANCH="${1:?usage: deploy.sh dev|main}"
shift || true

if [ "$BRANCH" = "main" ]; then
  APP="${FLY_SKEJ_GATEWAY_APP_PROD:-skej-at-prod-gateway}"
  APP_ENV_VALUE="prod"
  PUBLIC_ORIGIN_VALUE="${SKEJ_PUBLIC_ORIGIN_PROD:-https://skej.at}"
else
  APP="${FLY_SKEJ_GATEWAY_APP_DEV:-skej-at-dev-gateway}"
  APP_ENV_VALUE="dev"
  PUBLIC_ORIGIN_VALUE="${SKEJ_PUBLIC_ORIGIN_DEV:-https://testing.skej.at}"
fi

DEPLOY_ARGS=(
  --config "$SERVICE_DIR/fly.toml"
  --app "$APP"
  --remote-only
  --env "APP_ENV=$APP_ENV_VALUE"
  --env "SKEJ_PUBLIC_ORIGIN=$PUBLIC_ORIGIN_VALUE"
  --env "PUBLIC_ORIGIN=$PUBLIC_ORIGIN_VALUE"
  --env "SKEJ_SQLITE_PATH=/var/lib/skej-api/data/skej.sqlite"
)

cd "$SERVICE_DIR"

if command -v flyctl >/dev/null 2>&1; then
  exec flyctl deploy "${DEPLOY_ARGS[@]}" "$@"
fi
if command -v fly >/dev/null 2>&1; then
  exec fly deploy "${DEPLOY_ARGS[@]}" "$@"
fi

echo "Install flyctl to deploy: https://fly.io/docs/flyctl/install/" >&2
exit 1
