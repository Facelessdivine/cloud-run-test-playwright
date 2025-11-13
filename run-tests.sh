#!/usr/bin/env bash
set -euo pipefail

# These env vars are injected by Cloud Run Jobs for each task
IDX=$(( ${CLOUD_RUN_TASK_INDEX:-0} + 1 ))   # 1-based shard index
CNT=${CLOUD_RUN_TASK_COUNT:-1}              # total shards

RUN_ID=${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}
BUCKET=${BUCKET:?must set BUCKET (gs://...)}

echo "Running Playwright shard ${IDX}/${CNT} | RUN_ID=${RUN_ID}"

# Run this shard only, with blob reporter for later merge
npx playwright test \
  --shard="${IDX}/${CNT}" \
  --workers=1 \
  --reporter=blob

# Upload blob-report to GCS under this shard
DEST="${BUCKET}/runs/${RUN_ID}/blob/shard-${IDX}"
echo "Uploading blob-report/ to ${DEST}"
gcloud storage rsync --recursive ./blob-report "$DEST"
