#!/usr/bin/env bash
set -euo pipefail

# Shard info from Cloud Run Jobs
IDX=$(( ${CLOUD_RUN_TASK_INDEX:-0} + 1 ))  # 1-based index for Playwright
CNT=${CLOUD_RUN_TASK_COUNT:-1}

RUN_ID=${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}
BUCKET=${BUCKET:-"gs://pw-artifacts-demo-1763046256"}  # default if not provided

# Normalize BUCKET: if it doesn't start with gs://, add it
if [[ "$BUCKET" != gs://* ]]; then
  BUCKET="gs://${BUCKET}"
fi

echo "=== PW shard ${IDX}/${CNT} | RUN_ID=${RUN_ID} ==="
echo "BUCKET=${BUCKET}"

# Run Playwright for this shard only
npx playwright test \
  --shard="${IDX}/${CNT}" \
  --workers=1 \
  --reporter=blob

# Upload blob-report
DEST="${BUCKET}/runs/${RUN_ID}/blob/shard-${IDX}"
echo "Uploading blob-report to ${DEST}"
gcloud storage rsync --recursive ./blob-report "$DEST"
