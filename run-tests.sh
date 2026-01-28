#!/usr/bin/env bash
set -euo pipefail

############################################
# Shard info from Cloud Run Jobs
############################################

IDX=$(( ${CLOUD_RUN_TASK_INDEX:-0} + 1 ))
CNT=${CLOUD_RUN_TASK_COUNT:-1}
BUCKET="pw-artifacts-demo-1763046256"
RUN_ID=${RUN_ID:-${CLOUD_RUN_EXECUTION:-$(date -u +%Y%m%dT%H%M%SZ)}}

BUCKET="$(echo -n "$BUCKET" | xargs)"
[[ "$BUCKET" != gs://* ]] && BUCKET="gs://${BUCKET}"
BUCKET_NAME="${BUCKET#gs://}"

echo "===================================================="
echo "🚀 Playwright shard ${IDX}/${CNT}"
echo "RUN_ID=${RUN_ID}"
echo "BUCKET=${BUCKET}"
echo "===================================================="

############################################
# 1) Run this shard
############################################

echo "🧪 Running Playwright tests..."
npx playwright test \
  --shard="${IDX}/${CNT}" \
  --workers=1 \
  --reporter=blob

############################################
# 2) Upload blob report
############################################

DEST_PREFIX="runs/${RUN_ID}/blob/shard-${IDX}"
echo "📤 Uploading blob-report to gs://${BUCKET_NAME}/${DEST_PREFIX}"

node scripts/gcs.js upload "$BUCKET_NAME" "./blob-report" "$DEST_PREFIX"

############################################
# 3) Coordinator shard merges all
############################################

if [[ "$IDX" -eq 1 ]]; then
  echo "👑 Coordinator shard — waiting for ${CNT} shards..."

  WORK="/merge"
  mkdir -p "$WORK/blob" "$WORK/all-blob"
  cd "$WORK"

  max_wait_seconds=1800
  sleep_interval=10
  waited=0

  while true; do
    echo "🔍 Checking shard folders..."
    shard_count=$(node /app/scripts/gcs.js count "$BUCKET_NAME" "$RUN_ID") || true
    echo "Found ${shard_count}/${CNT} shards"

    [[ "$shard_count" -ge "$CNT" ]] && break

    if [[ "$waited" -ge "$max_wait_seconds" ]]; then
      echo "❌ ERROR: Timeout waiting for shards."
      exit 1
    fi

    sleep "$sleep_interval"
    waited=$((waited + sleep_interval))
  done

  ############################################
  # Download blobs
  ############################################

  echo "📥 Downloading shard blobs..."
  node /app/scripts/gcs.js download "$BUCKET_NAME" "runs/${RUN_ID}/blob/" "./blob"

  ############################################
  # Flatten zip files
  ############################################

  echo "📦 Collecting blob zip files..."
  find ./blob -type f -name '*.zip' -exec cp {} ./all-blob/ \;

  if [[ -z "$(ls -A ./all-blob)" ]]; then
    echo "❌ ERROR: No blob zip files found."
    exit 1
  fi

  ############################################
  # Merge reports
  ############################################

  echo "🖥️ Generating HTML report..."
  npx playwright merge-reports --reporter html ./all-blob

  echo "📄 Generating JUnit report..."
  npx playwright merge-reports --reporter junit ./all-blob > ./results.xml || {
    echo "⚠️ JUnit merge failed — writing empty fallback file."
    echo '<?xml version="1.0" encoding="UTF-8"?><testsuites></testsuites>' > ./results.xml
  }

  ############################################
  # Upload merged reports
  ############################################

  echo "📤 Uploading merged HTML..."
  node /app/scripts/gcs.js upload "$BUCKET_NAME" "./playwright-report" "runs/${RUN_ID}/final/html"

  echo "📤 Uploading merged JUnit..."
  node /app/scripts/gcs.js upload "$BUCKET_NAME" "./results.xml" "runs/${RUN_ID}/final/junit.xml"

  echo "===================================================="
  echo "✅ MERGE COMPLETED"
  echo "🔗 HTML:  gs://${BUCKET_NAME}/runs/${RUN_ID}/final/html/index.html"
  echo "🔗 JUnit: gs://${BUCKET_NAME}/runs/${RUN_ID}/final/junit.xml"
  echo "===================================================="
else
  echo "Shard ${IDX}/${CNT} finished — merge handled by shard 1."
fi