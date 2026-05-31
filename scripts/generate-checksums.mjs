import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const dist = path.join(root, "dist");
const artifacts = [
  "Tacket.dmg",
  "tacket-chrome-extension.zip"
];

const lines = [];
for (const artifact of artifacts) {
  const file = path.join(dist, artifact);
  const bytes = await readFile(file);
  const hash = createHash("sha256").update(bytes).digest("hex");
  lines.push(`${hash}  ${artifact}`);
}

const output = path.join(dist, "SHA256SUMS");
await writeFile(output, `${lines.join("\n")}\n`);
console.log(output);
