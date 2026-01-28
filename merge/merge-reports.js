import { Storage } from "@google-cloud/storage";
import fs from "fs/promises";
import path from "path";

const bucketName = process.env.BUCKET;
const runId = process.env.RUN_ID;
const prefix = `runs/${runId}/blob/`;
const localDir = "./blob-reports";

if (!bucketName || !runId) {
  throw new Error("BUCKET and RUN_ID env vars must be set");
}

const storage = new Storage();

async function main() {
  console.log(`📥 Downloading shards from gs://${bucketName}/${prefix}`);

  await fs.mkdir(localDir, { recursive: true });

  const [files] = await storage.bucket(bucketName).getFiles({ prefix });

  if (!files.length) {
    throw new Error("No shard files found in bucket");
  }

  for (const file of files) {
    const dest = path.join(localDir, path.basename(file.name));
    await file.download({ destination: dest });
    console.log(`Downloaded: ${dest}`);
  }

  console.log("🧩 Merging Playwright blob reports...");
  const { execSync } = await import("child_process");
  execSync("npx playwright merge-reports --reporter html ./blob-reports", {
    stdio: "inherit",
  });

  console.log("✅ Report merged successfully");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
