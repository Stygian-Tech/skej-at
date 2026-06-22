#!/usr/bin/env bash
# Full local CI entrypoint.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash scripts/ci-js.sh
bash scripts/ci-swift.sh
