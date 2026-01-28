#!/usr/bin/env bash
set -euo pipefail

############################################
# Shard info from Cloud Run Jobs
############################################

IDX=$(( ${CLOUD_RUN_TASK_INDEX:-0} + 1 ))  # Playwright shards are 1-based
CNT=${CLOUD_RUN_TASK_COUNT:-1}

RUN_ID=${RUN_ID:-${CLOUD_RUN_EXECUTION:-$(date -u +%Y%m%dT%H%M%SZ)}}
BUCKET=${BUCKET:-"gs://pw-artifacts-demo-1763046256"}

BUCKET="$(echo -n "$BUCKET" | xargs)"
[[ "$BUCKET" != gs://* ]] && BUCKET="gs://${BUCKET}"

echo "===================================================="
echo "🚀 PW SHARD ${IDX}/${CNT}"
echo "RUN_ID=${RUN_ID}"
echo "BUCKET=${BUCKET}"
echo "===================================================="

############################################
# 1) Run this shard's tests
############################################

echo "🧪 Running Playwright shard ${IDX}/${CNT}..."
npx playwright test \
  --shard="${IDX}/${CNT}" \
  --workers=1 \
  --reporter=blob

############################################
# 2) Upload blob report
############################################

DEST="${BUCKET}/runs/${RUN_ID}/blob/shard-${IDX}"
echo "📤 Uploading blob-report to ${DEST}"
gcloud storage rsync --recursive ./blob-report "$DEST"

############################################
# 3) Coordinator shard (IDX == 1) merges all
############################################

if [[ "$IDX" -eq 1 ]]; then
  echo "👑 Coordinator shard. Waiting for ${CNT} shards..."

  WORK="/merge"
  mkdir -p "$WORK/all-blob"
  cd "$WORK"

  max_wait_seconds=1800
  sleep_interval=10
  waited=0

  while true; do
    echo "🔍 Checking shard folders in ${BUCKET}/runs/${RUN_ID}/blob/..."
    shard_count=$(gcloud storage ls "${BUCKET}/runs/${RUN_ID}/blob/" | grep -c "shard-") || true
    echo "Found ${shard_count}/${CNT} shards"

    [[ "$shard_count" -ge "$CNT" ]] && break

    if [[ "$waited" -ge "$max_wait_seconds" ]]; then
      echo "❌ ERROR: Timeout waiting for all shards."
      exit 1
    fi

    sleep "$sleep_interval"
    waited=$((waited + sleep_interval))
  done

  ############################################
  # Download all blobs
  ############################################

  echo "📥 Downloading all shard blobs..."
  gcloud storage rsync --recursive "${BUCKET}/runs/${RUN_ID}/blob" ./blob

  ############################################
  # Flatten ZIPs for merge
  ############################################

  echo "📦 Collecting .zip files..."
  find ./blob -type f -name '*.zip' -exec cp {} ./all-blob/ \;

  if [[ -z "$(ls -A ./all-blob)" ]]; then
    echo "❌ ERROR: No blob zip files found for merge."
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
  gcloud storage rsync --recursive ./playwright-report "${BUCKET}/runs/${RUN_ID}/final/html"

  echo "📤 Uploading merged JUnit..."
  gcloud storage cp ./results.xml "${BUCKET}/runs/${RUN_ID}/final/junit.xml"

  echo "===================================================="
  echo "✅ MERGE COMPLETED"
  echo "🔗 HTML:  ${BUCKET}/runs/${RUN_ID}/final/html/index.html"
  echo "🔗 JUnit: ${BUCKET}/runs/${RUN_ID}/final/junit.xml"
  echo "===================================================="
else
  echo "Shard ${IDX}/${CNT} finished — merge handled by shard 1."
fi