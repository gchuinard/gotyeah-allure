#!/usr/bin/env bash
# Build the unified Allure report from every site's results, preserving the
# history folder so trend curves survive across runs. Idempotent + locked.
set -euo pipefail

ROOT="${ALLURE_ROOT:-/allure}"
RESULTS="$ROOT/results"     # one sub-dir per site, pushed by each repo's CI
HISTORY="$ROOT/history"     # persisted across runs → trend curves
REPORT="$ROOT/report"       # served by the nginx container
STAGING="$ROOT/.staging"
TMP="$ROOT/.report.tmp"
LOCK="$ROOT/.generate.lock"

mkdir -p "$RESULTS" "$HISTORY" "$REPORT"

# Serialize generations (concurrent CI pushes + heartbeat could overlap).
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "[generate] another generation holds the lock — skipping"
  exit 0
fi

rm -rf "$STAGING" "$TMP"
mkdir -p "$STAGING/history"

# 1. Aggregate every site's result files into one staging dir.
#    All allure files are UUID-named (…-result.json / …-container.json /
#    …-attachment.*) so flattening many sites into one dir never collides.
shopt -s nullglob
sites=0
for site in "$RESULTS"/*/; do
  [ -d "$site" ] || continue
  cp -a "$site". "$STAGING"/ 2>/dev/null || true
  sites=$((sites + 1))
done
echo "[generate] aggregated $sites site(s) from $RESULTS"

# 2. Restore persisted history so the trend widgets keep their data points.
if [ -n "$(ls -A "$HISTORY" 2>/dev/null || true)" ]; then
  cp -a "$HISTORY"/. "$STAGING/history/" 2>/dev/null || true
fi

# 3. Generate the unified report into a temp dir.
allure generate "$STAGING" -o "$TMP" --clean

# 4. Persist the freshly-computed history for the next generation.
if [ -d "$TMP/history" ]; then
  rm -rf "$HISTORY"
  mkdir -p "$HISTORY"
  cp -a "$TMP/history/." "$HISTORY"/ 2>/dev/null || true
fi

# 5. Publish IN PLACE, preserving the $REPORT directory inode. A mv-swap would
#    replace the inode and leave the nginx bind-mount viewing a stale/empty dir
#    (→ 403). We instead clear the dir contents and copy the new report in.
mkdir -p "$REPORT"
find "$REPORT" -mindepth 1 -delete 2>/dev/null || true
cp -a "$TMP/." "$REPORT/"
rm -rf "$TMP" "$STAGING"

echo "[generate] unified report ready ($sites site(s)) at $(date -u +%FT%TZ)"
