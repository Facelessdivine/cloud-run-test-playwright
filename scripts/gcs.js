import { Storage } from "@google-cloud/storage";
import fs from "fs";
import path from "path";

const storage = new Storage();

export async function uploadDir(bucketName, srcDir, destPrefix) {
  const bucket = storage.bucket(bucketName);

  async function walk(dir) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    const files = [];
    for (const e of entries) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) files.push(...(await walk(p)));
      else files.push(p);
    }
    return files;
  }

  const files = await walk(srcDir);
  for (const f of files) {
    const rel = path.relative(srcDir, f);
    const dest = path.posix.join(destPrefix, rel);
    await bucket.upload(f, { destination: dest });
    console.log("Uploaded:", dest);
  }
}

export async function downloadPrefix(bucketName, prefix, destDir) {
  const bucket = storage.bucket(bucketName);
  const [files] = await bucket.getFiles({ prefix });

  for (const f of files) {
    if (f.name.endsWith("/")) continue;
    const out = path.join(destDir, f.name.replace(prefix, ""));
    fs.mkdirSync(path.dirname(out), { recursive: true });
    await f.download({ destination: out });
    console.log("Downloaded:", f.name);
  }
}

export async function countShardFolders(bucketName, runId) {
  const bucket = storage.bucket(bucketName);
  const [files] = await bucket.getFiles({
    prefix: `runs/${runId}/blob/shard-`,
  });
  const shards = new Set(files.map((f) => f.name.split("/")[3]));
  return shards.size;
}
if (process.argv[2]) {
  const [, , cmd, bucket, ...args] = process.argv;

  if (cmd === "upload") {
    const [src, dest] = args;
    await uploadDir(bucket, src, dest);
  } else if (cmd === "download") {
    const [prefix, dest] = args;
    await downloadPrefix(bucket, prefix, dest);
  } else if (cmd === "count") {
    const [runId] = args;
    const n = await countShardFolders(bucket, runId);
    console.log(n);
  } else {
    console.error("Unknown command:", cmd);
    process.exit(1);
  }
}
