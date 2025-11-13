#!/usr/bin/env bash
set -euo pipefail

# Shard info from Cloud Run Jobs
IDX=$(( ${CLOUD_RUN_TASK_INDEX:-0} + 1 ))  # 1-based index for Playwright
CNT=${CLOUD_RUN_TASK_COUNT:-1}

# Prefer explicit RUN_ID, otherwise use Cloud Run execution id, otherwise fallback to timestamp
RUN_ID=${RUN_ID:-${CLOUD_RUN_EXECUTION:-$(date -u +%Y%m%dT%H%M%SZ)}}

BUCKET=${BUCKET:-"gs://pw-artifacts-demo-1763046256"}  # default

# Trim whitespace, normalize BUCKET
BUCKET="$(echo -n "$BUCKET" | xargs)"
if [[ "$BUCKET" != gs://* ]]; then
  BUCKET="gs://${BUCKET}"
fi

echo "=== PW shard ${IDX}/${CNT} | RUN_ID=${RUN_ID} ==="
echo "BUCKET='${BUCKET}'"

############################################
# 1) Run this shard's tests + upload blob
############################################

npx playwright test \
  --shard="${IDX}/${CNT}" \
  --workers=1 \
  --reporter=blob

DEST="${BUCKET}/runs/${RUN_ID}/blob/shard-${IDX}"
echo "Uploading blob-report to ${DEST}"
gcloud storage rsync --recursive ./blob-report "$DEST"

############################################
# 2) Coordinator shard (IDX == 1) merges all
############################################

if [[ "$IDX" -eq 1 ]]; then
  echo "Coordinator shard: waiting for all ${CNT} shards to upload blobs..."

  WORK=/merge
  mkdir -p "$WORK/all-blob"
  cd "$WORK"

  # Wait for all shard-* folders to appear in GCS
  max_wait_seconds=1800   # 30 minutes
  sleep_interval=10
  waited=0

  while true; do
    echo "Checking shard folders in ${BUCKET}/runs/${RUN_ID}/blob/ ..."
    # List shard-* prefixes
    shard_count=$(gcloud storage ls "${BUCKET}/runs/${RUN_ID}/blob/" \
      | grep -c "shard-") || true

    echo "Found ${shard_count}/${CNT} shard folders"

    if [[ "$shard_count" -ge "$CNT" ]]; then
      echo "All shards present. Proceeding to merge."
      break
    fi

    if [[ "$waited" -ge "$max_wait_seconds" ]]; then
      echo "ERROR: Timeout waiting for all shards (${CNT}) to appear in GCS."
      exit 1
    fi

    sleep "$sleep_interval"
    waited=$((waited + sleep_interval))
  done

  # Download all blobs
  echo "Downloading all shard blobs..."
  gcloud storage rsync --recursive "${BUCKET}/runs/${RUN_ID}/blob" ./blob

  echo "Collecting blob zip files..."
  find ./blob -type f -name '*.zip' -print0 | while IFS= read -r -d '' f; do
    cp "$f" ./all-blob/
  done

  echo "Merging Playwright reports..."
  npx playwright merge-reports --reporter html ./all-blob
  npx playwright merge-reports --reporter junit ./all-blob

  echo "Uploading merged reports..."
  gcloud storage rsync --recursive ./playwright-report "${BUCKET}/runs/${RUN_ID}/final/html"
  gcloud storage cp ./results.xml "${BUCKET}/runs/${RUN_ID}/final/junit.xml"

  echo "DONE!"
  echo "HTML:  ${BUCKET}/runs/${RUN_ID}/final/html/index.html"
  echo "JUnit: ${BUCKET}/runs/${RUN_ID}/final/junit.xml"
else
  echo "Shard ${IDX}/${CNT} finished; merge will be done by shard 1."
fi
