#!/usr/bin/env bash
# Watch the central results dir and regenerate the unified report whenever a
# repo's CI pushes new results. A timeout on inotifywait doubles as a periodic
# heartbeat so the report is rebuilt even if a filesystem event is missed.
set -euo pipefail

ROOT="${ALLURE_ROOT:-/allure}"
RESULTS="$ROOT/results"
HEARTBEAT="${ALLURE_HEARTBEAT:-900}"   # seconds; also the max staleness window

mkdir -p "$RESULTS"

echo "[watch] initial generation"
generate.sh || echo "[watch] initial generation failed (continuing)"

echo "[watch] watching $RESULTS (heartbeat ${HEARTBEAT}s)"
while true; do
  # Block until a change OR the heartbeat elapses, then debounce a burst of
  # rsync writes before regenerating.
  timeout "$HEARTBEAT" inotifywait -r -q \
    -e close_write,moved_to,create,delete "$RESULTS" >/dev/null 2>&1 || true
  sleep 5
  generate.sh || echo "[watch] generation failed (continuing)"
done
