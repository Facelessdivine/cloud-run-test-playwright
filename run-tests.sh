#!/bin/bash
set -euo pipefail

echo "🧪 Running Playwright tests..."
BUCKET="pw-artifacts-demo-1763046256"
BUCKET=${BUCKET:?BUCKET env var required}
RUN_ID=${RUN_ID:-pw-tests-$(date +%s)}
SHARD_INDEX=${SHARD_INDEX:-1}
SHARD_TOTAL=${SHARD_TOTAL:-1}

export RUN_ID
export SHARD_INDEX
export SHARD_TOTAL
export BUCKET

npx playwright test --shard=$SHARD_INDEX/$SHARD_TOTAL --reporter=blob

echo "📤 Uploading blob report shard..."

gsutil -m cp -r blob-report "gs://${BUCKET}/runs/${RUN_ID}/blob/shard-${SHARD_INDEX}"

echo "✅ Shard upload complete"

# Coordinator only
if [[ "$SHARD_INDEX" == "1" ]]; then
  echo "👑 Coordinator shard — waiting for $SHARD_TOTAL shards..."

  EXPECTED=$SHARD_TOTAL
  FOUND=0

  while [[ "$FOUND" -lt "$EXPECTED" ]]; do
    sleep 5
    FOUND=$(gsutil ls "gs://${BUCKET}/runs/${RUN_ID}/blob/" | wc -l)
    echo "Found $FOUND/$EXPECTED shards..."
  done

  echo "🧩 All shards uploaded — merging reports..."

  node ./merge/merge-reports.js

  echo "🎉 Final report ready"
fi