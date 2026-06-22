#!/usr/bin/env bash
# Detect changed path filters for CI without third-party marketplace actions.
set -euo pipefail

BASE=""
HEAD="${GITHUB_SHA:?GITHUB_SHA is required}"
MATCH_ALL=0

case "${GITHUB_EVENT_NAME:-}" in
  pull_request)
    BASE="${GITHUB_EVENT_PULL_REQUEST_BASE_SHA:-}"
    if [ -z "$BASE" ]; then
      MATCH_ALL=1
    fi
    ;;
  push)
    BASE="${GITHUB_EVENT_BEFORE:-}"
    if [ -z "$BASE" ] || [ "$BASE" = "0000000000000000000000000000000000000000" ]; then
      MATCH_ALL=1
    fi
    ;;
  *)
    MATCH_ALL=1
    ;;
esac

to_pathspec() {
  local spec="$1"
  if [[ "$spec" == *"*"* ]]; then
    printf ':(glob)%s' "$spec"
  else
    printf '%s' "$spec"
  fi
}

filter_changed() {
  local name="$1"
  shift
  local out="${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

  if [ "$MATCH_ALL" = "1" ]; then
    echo "${name}=true" >> "$out"
    return
  fi

  local spec pathspec
  for spec in "$@"; do
    pathspec="$(to_pathspec "$spec")"
    if git diff --name-only "$BASE" "$HEAD" -- "$pathspec" | grep -q .; then
      echo "${name}=true" >> "$out"
      return
    fi
  done

  echo "${name}=false" >> "$out"
}

filter_changed gateway \
  'services/skej-api/**' \
  'scripts/ci-swift.sh' \
  'scripts/fly-deploy-gateway.sh' \
  '.github/workflows/ci.yml' \
  '.dockerignore'

filter_changed web \
  'apps/web/**' \
  'packages/lexicons/**' \
  'package.json' \
  'bun.lock' \
  'turbo.json' \
  'scripts/ci-js.sh' \
  '.github/workflows/ci.yml'
