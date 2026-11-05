import fs from "node:fs";
import path from "node:path";

const required = [
  "docs/README.md", "docs/architecture/README.md", "docs/testing/README.md",
  "docs/testing/tooling.md", "docs/agents/README.md", "docs/roadmap.md",
  "docs/operations/dependencies.md", "docs/windows/README.md",
  "docs/android/README.md"
];
const missing = required.filter((file) => !fs.existsSync(path.resolve(file)));
if (missing.length) {
  console.error(`missing canonical docs: ${missing.join(", ")}`);
  process.exit(1);
}
console.log(`ok: ${required.length} canonical documents`);
