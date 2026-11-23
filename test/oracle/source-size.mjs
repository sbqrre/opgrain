
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../../", import.meta.url));
const files = readdirSync(root).filter(name => name.endsWith(".mbt") && !/_(?:wb)?test\.mbt$/.test(name)).sort();
const details = files.map(name => {
  const source = readFileSync(new URL("../../" + name, import.meta.url), "utf8").replace(/\r\n/g, "\n");
  const lines = source.replace(/\n$/, "").split("\n");
  const blank = lines.filter(line => !line.trim()).length;
  const comments = lines.filter(line => line.trimStart().startsWith("//")).length;
  return { file: name, physical: lines.length, blank, comments, effective: lines.length - blank - comments };
});
const total = details.reduce((sum, item) => ({
  physical: sum.physical + item.physical, blank: sum.blank + item.blank,
  comments: sum.comments + item.comments, effective: sum.effective + item.effective,
}), { physical: 0, blank: 0, comments: 0, effective: 0 });
console.log(JSON.stringify({ package: "sbqrre/opgrain", scope: "root library package, excluding tests, examples, benchmarks and generated interfaces", files: details.length, total, details }, null, 2));
