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
SWIFT_PACKAGE_FLAGS=()

if [ "${SKEJ_DISABLE_SWIFTPM_SANDBOX:-}" = "1" ]; then
  SWIFT_PACKAGE_FLAGS+=(--disable-sandbox)
fi

run_tests() {
  swift test ${SWIFT_PACKAGE_FLAGS[@]+"${SWIFT_PACKAGE_FLAGS[@]}"} --package-path "$PACKAGE_PATH"
}

run_build() {
  if [ "${SKEJ_DISABLE_SWIFTPM_SANDBOX:-}" = "1" ] && [ -d "/Library/Developer/CommandLineTools" ]; then
    DEVELOPER_DIR="/Library/Developer/CommandLineTools" \
      swift build ${SWIFT_PACKAGE_FLAGS[@]+"${SWIFT_PACKAGE_FLAGS[@]}"} -c release --package-path "$PACKAGE_PATH"
  else
    swift build ${SWIFT_PACKAGE_FLAGS[@]+"${SWIFT_PACKAGE_FLAGS[@]}"} -c release --package-path "$PACKAGE_PATH"
  fi
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
