// Indexes the API reference for the site's <Api> links:
//
//   node api-index.mjs <TypeDoc out dir> <index.json>
//
// It maps each name that the package exports to its page in TypeDoc's
// output, with its members' anchors.
import fs from "node:fs";
import path from "node:path";

const [reference, out] = process.argv.slice(2);
if (out === undefined) {
  console.error("usage: api-index.mjs <TypeDoc out dir> <index.json>");
  process.exit(2);
}

const index = {};
// TypeDoc writes a page of each kind of symbol into its own directory.
for (const kind of [
  "classes",
  "enums",
  "functions",
  "interfaces",
  "types",
  "variables",
]) {
  const dir = path.join(reference, kind);
  if (!fs.existsSync(dir)) {
    continue;
  }
  for (const file of fs.readdirSync(dir)) {
    const html = fs.readFileSync(path.join(dir, file), "utf8");
    const anchors = [...html.matchAll(/\bid="([^"]+)"/g)].map(
      (match) => match[1],
    );
    index[path.basename(file, ".html")] = {
      url: `api/${kind}/${file}`,
      anchors: [...new Set(anchors)],
    };
  }
}
if (Object.keys(index).length === 0) {
  throw new Error(`${reference} has no TypeDoc pages`);
}

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, `${JSON.stringify(index, null, 2)}\n`);
console.log(`Indexed ${Object.keys(index).length} names of the API reference.`);
