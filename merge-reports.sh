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

# Inside the Coordinator shard block (IDX == 1)
WORK="/merge"
mkdir -p "$WORK/all-blob"
cd "$WORK"

echo "Merging reports..."
# Explicitly use the directory as the last argument
npx playwright merge-reports --reporter html "$WORK/all-blob"
npx playwright merge-reports --reporter junit "$WORK/all-blob" > "$WORK/results.xml"


# DEBUG: List files to see exactly what was created
echo "Files in $WORK:"
ls -lh "$WORK"

# Check if file exists before trying to upload
if [[ ! -f "$WORK/results.xml" ]]; then
  echo "ERROR: $WORK/results.xml was not found. Merge command likely failed."
  exit 1
fi

echo "Uploading merged reports..."
gcloud storage rsync --recursive "$WORK/playwright-report" "${BUCKET}/runs/${RUN_ID}/final/html"
gcloud storage cp "$WORK/results.xml" "${BUCKET}/runs/${RUN_ID}/final/junit.xml"

echo "  JUnit: ${BUCKET}/runs/${RUN_ID}/final/junit.xml"
