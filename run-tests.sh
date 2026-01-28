#!/usr/bin/env bash
set -euo pipefail

############################################
# Shard info from Cloud Run Jobs
############################################

IDX=$(( ${CLOUD_RUN_TASK_INDEX:-0} + 1 ))
CNT=${CLOUD_RUN_TASK_COUNT:-1}
BUCKET="pw-artifacts-demo-1763046256"
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
# Helper: upload directory to GCS via Node SDK
############################################

upload_dir() {
  local src="$1"
  local dest="$2"

  node <<EOF
import { Storage } from '@google-cloud/storage';
import fs from 'fs';
import path from 'path';

const bucketName = "${BUCKET_NAME}";
const prefix = "${dest}";
const storage = new Storage();

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(d =>
    d.isDirectory() ? walk(path.join(dir, d.name)) : [path.join(dir, d.name)]
  );
}

const files = walk("${src}");
for (const f of files) {
  const rel = path.relative("${src}", f);
  const destPath = prefix + '/' + rel;
  await storage.bucket(bucketName).upload(f, { destination: destPath });
  console.log("Uploaded:", destPath);
}
EOF
}

############################################
# Helper: download prefix from GCS
############################################

download_prefix() {
  local prefix="$1"
  local dest="$2"

  node <<EOF
import { Storage } from '@google-cloud/storage';
import fs from 'fs';
import path from 'path';

const bucketName = "${BUCKET_NAME}";
const prefix = "${prefix}";
const dest = "${dest}";
const storage = new Storage();

const [files] = await storage.bucket(bucketName).getFiles({ prefix });
for (const f of files) {
  if (f.name.endsWith('/')) continue;
  const out = path.join(dest, f.name.replace(prefix, ''));
  fs.mkdirSync(path.dirname(out), { recursive: true });
  await f.download({ destination: out });
  console.log("Downloaded:", f.name);
}
EOF
}

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
upload_dir "./blob-report" "$DEST_PREFIX"

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
import { Storage } from '@google-cloud/storage';
const storage = new Storage();
const [files] = await storage.bucket("${BUCKET_NAME}")
  .getFiles({ prefix: "runs/${RUN_ID}/blob/shard-" });
const shards = new Set(files.map(f => f.name.split('/')[3]));
console.log(shards.size);
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
  download_prefix "runs/${RUN_ID}/blob/" "./blob"

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
  upload_dir "./playwright-report" "runs/${RUN_ID}/final/html"

  echo "📤 Uploading merged JUnit..."
  node <<EOF
import { Storage } from '@google-cloud/storage';
const storage = new Storage();
await storage.bucket("${BUCKET_NAME}")
  .upload("./results.xml", { destination: "runs/${RUN_ID}/final/junit.xml" });
console.log("Uploaded results.xml");
EOF

  echo "===================================================="
  echo "✅ MERGE COMPLETED"
  echo "🔗 HTML:  gs://${BUCKET_NAME}/runs/${RUN_ID}/final/html/index.html"
  echo "🔗 JUnit: gs://${BUCKET_NAME}/runs/${RUN_ID}/final/junit.xml"
  echo "===================================================="
else
  echo "Shard ${IDX}/${CNT} finished — merge handled by shard 1."
fi