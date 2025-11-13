#!/usr/bin/env bash
set -euo pipefail

RUN_ID=${RUN_ID:?must set RUN_ID}
BUCKET=${BUCKET:?must set BUCKET (gs://...)}

WORK=/merge
mkdir -p "$WORK"/all-blob
cd "$WORK"

echo "Syncing blobs for RUN_ID=${RUN_ID}"
gcloud storage rsync --recursive "${BUCKET}/runs/${RUN_ID}/blob" ./blob

# Collect all shard blob-report folders into ./all-blob
find ./blob -type d -name blob-report -print0 | while IFS= read -r -d '' d; do
  # e.g. /merge/blob/shard-1/blob-report → all-blob/shard-1
  shard_name=$(basename "$(dirname "$d")")
  mkdir -p "./all-blob/${shard_name}"
  cp -R "$d"/. "./all-blob/${shard_name}/"
done

echo "Merging reports…"

# HTML report
npx playwright merge-reports --reporter html ./all-blob
# JUnit report
npx playwright merge-reports --reporter junit ./all-blob

# Upload final unified reports
gcloud storage rsync --recursive ./playwright-report "${BUCKET}/runs/${RUN_ID}/final/html"
gcloud storage cp ./results.xml "${BUCKET}/runs/${RUN_ID}/final/junit.xml"

echo "DONE:"
echo "  HTML:  ${BUCKET}/runs/${RUN_ID}/final/html/index.html"
echo "  JUnit: ${BUCKET}/runs/${RUN_ID}/final/junit.xml"
