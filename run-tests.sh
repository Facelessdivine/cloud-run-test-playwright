#!/usr/bin/env bash
set -euo pipefail

############################################
# Shard info from Cloud Run Jobs
############################################
BUCKET="pw-artifacts-demo-1763046256"
IDX=$(( ${CLOUD_RUN_TASK_INDEX:-0} + 1 ))
CNT=${CLOUD_RUN_TASK_COUNT:-1}
RUN_ID=${RUN_ID:-${CLOUD_RUN_EXECUTION:-$(date -u +%Y%m%dT%H%M%SZ)}}
BUCKET=${BUCKET:?ERROR: BUCKET env var is required}

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

node <<EOF
import { uploadDir } from './scripts/gcs.js';
await uploadDir("${BUCKET_NAME}", "./blob-report", "${DEST_PREFIX}");
EOF

############################################
# 3) Coordinator shard merges all
############################################

if [[ "$IDX" -eq 1 ]]; then
  echo "👑 Coordinator shard — waiting for ${CNT} shards..."

  WORK="/merge"
  mkdir -p "$WORK/all-blob"
  cd "$WORK"

  max_wait_seconds=1800
  sleep_interval=10
  waited=0

  while true; do
    echo "🔍 Checking shard folders..."
    shard_count=$(node <<EOF
import { countShardFolders } from '/app/scripts/gcs.js';
console.log(await countShardFolders("${BUCKET_NAME}", "${RUN_ID}"));
EOF
) || true

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
  node <<EOF
import { downloadPrefix } from '/app/scripts/gcs.js';
await downloadPrefix("${BUCKET_NAME}", "runs/${RUN_ID}/blob/", "./blob");
EOF

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
  node <<EOF
import { uploadDir } from '/app/scripts/gcs.js';
await uploadDir("${BUCKET_NAME}", "./playwright-report", "runs/${RUN_ID}/final/html");
EOF

  echo "📤 Uploading merged JUnit..."
  node <<EOF
import { uploadFile } from '/app/scripts/gcs.js';
await uploadFile("${BUCKET_NAME}", "./results.xml", "runs/${RUN_ID}/final/junit.xml");
EOF
  echo "📤 Deleting blob files..."
  node <<EOF
import { deleteFile } from '/app/scripts/gcs.js';
await deleteFile("${BUCKET_NAME}", "runs/${RUN_ID}/blob");
EOF
############################################
# 4) Cleanup blob artifacts
############################################

echo "🧹 Cleaning up shard blobs..."
node <<EOF
import { deletePrefix } from '/app/scripts/gcs.js';
await deletePrefix("${BUCKET_NAME}", "runs/${RUN_ID}/blob/");
EOF

  echo "===================================================="
  echo "✅ MERGE COMPLETED"
  echo "🔗 HTML:  gs://${BUCKET_NAME}/runs/${RUN_ID}/final/html/index.html"
  echo "🔗 JUnit: gs://${BUCKET_NAME}/runs/${RUN_ID}/final/junit.xml"
  echo "===================================================="
else
  echo "Shard ${IDX}/${CNT} finished — merge handled by shard 1."
fi