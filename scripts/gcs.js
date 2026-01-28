import { Storage } from "@google-cloud/storage";
import fs from "fs";
import path from "path";

const storage = new Storage();

function walk(dir) {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .flatMap((d) =>
      d.isDirectory() ? walk(path.join(dir, d.name)) : [path.join(dir, d.name)],
    );
}

export async function uploadDir(bucketName, srcDir, destPrefix) {
  const files = walk(srcDir);
  for (const f of files) {
    const rel = path.relative(srcDir, f);
    const dest = `${destPrefix}/${rel}`;
    await storage.bucket(bucketName).upload(f, { destination: dest });
    console.log("Uploaded:", dest);
  }
}

export async function uploadFile(bucketName, filePath, destPath) {
  await storage.bucket(bucketName).upload(filePath, { destination: destPath });
  console.log("Uploaded:", destPath);
}
export async function deleteFile(bucketName, filePath) {
  await storage.bucket(bucketName).file(filePath).delete();
  console.log("Deleted:", filePath);
}

export async function downloadPrefix(bucketName, prefix, destDir) {
  const [files] = await storage.bucket(bucketName).getFiles({ prefix });
  for (const f of files) {
    if (f.name.endsWith("/")) continue;
    const out = path.join(destDir, f.name.replace(prefix, ""));
    fs.mkdirSync(path.dirname(out), { recursive: true });
    await f.download({ destination: out });
    console.log("Downloaded:", f.name);
  }
}

export async function countShardFolders(bucketName, runId) {
  const [files] = await storage
    .bucket(bucketName)
    .getFiles({ prefix: `runs/${runId}/blob/shard-` });

  return new Set(files.map((f) => f.name.split("/")[3])).size;
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
