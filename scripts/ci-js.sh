#!/usr/bin/env bash
# Web and lexicon checks for CI and local verification.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bun install --frozen-lockfile
bun run lint
bun run typecheck
bun run test:web
bun run build:web
