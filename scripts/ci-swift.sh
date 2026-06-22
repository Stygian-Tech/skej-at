#!/usr/bin/env bash
# Skej gateway Swift checks for CI and local verification.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -n "${DEVELOPER_DIR:-}" ] && [ ! -d "$DEVELOPER_DIR" ]; then
  unset DEVELOPER_DIR
fi

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

MODE="${1:-all}"
PACKAGE_PATH="services/skej-api"

run_tests() {
  swift test --package-path "$PACKAGE_PATH"
}

run_build() {
  swift build -c release --package-path "$PACKAGE_PATH"
}

case "$MODE" in
  all)
    run_tests
    run_build
    ;;
  test)
    run_tests
    ;;
  build)
    run_build
    ;;
  *)
    echo "usage: ci-swift.sh [all|test|build]" >&2
    exit 64
    ;;
esac
