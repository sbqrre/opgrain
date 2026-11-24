import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));
const ignored = new Set([".git", "_build", ".mooncakes", "node_modules"]);
const files = [];
function walk(directory, prefix = "") {
  for (const item of readdirSync(directory, { withFileTypes: true })) {
    if (ignored.has(item.name)) continue;
    const path = prefix + item.name;
    if (item.isDirectory()) walk(join(directory, item.name), path + "/");
    else if (item.isFile() && /\.mbti?$/.test(item.name)) files.push(path);
  }
}
walk(root);
files.sort();

function measure(path) {
  const source = readFileSync(join(root, path), "utf8").replaceAll("\r\n", "\n");
  const lines = source === "" ? [] : source.replace(/\n$/, "").split("\n");
  const blank = lines.filter(line => !line.trim()).length;
  const comments = lines.filter(line => line.trimStart().startsWith("//")).length;
  return { file: path, physical: lines.length, blank, comments, effective: lines.length - blank - comments };
}
function classify(path) {
  if (path.endsWith(".mbti")) return "generated_interfaces";
  const header = readFileSync(join(root, path), "utf8").slice(0, 2048);
  if (/^\/\/ Generated\b/m.test(header)) return "generated_fixtures";
  if (path.startsWith("examples/")) return "examples";
  if (path.startsWith("benchmarks/")) return "benchmarks";
  if (path.startsWith("test/")) return "test_drivers";
  if (/_(?:wb)?test\.mbt$/.test(path)) return "handwritten_tests";
  return path.includes("/") ? "other_sources" : "core";
}
const categories = {};
for (const path of files) (categories[classify(path)] ??= []).push(measure(path));
function total(items) {
  return items.reduce((sum, item) => ({
    physical: sum.physical + item.physical,
    blank: sum.blank + item.blank,
    comments: sum.comments + item.comments,
    effective: sum.effective + item.effective,
  }), { physical: 0, blank: 0, comments: 0, effective: 0 });
}
const core = categories.core ?? [];
console.log(JSON.stringify({
  package: "sbqrre/opgrain",
  scope: "root library package, excluding tests, examples, benchmarks and generated interfaces",
  counting: "nonblank lines excluding whole-line // comments; inline comments retain their code line",
  files: core.length,
  total: total(core),
  categories: Object.fromEntries(Object.entries(categories).map(([name, items]) =>
    [name, { files: items.length, ...total(items) }])),
  details: core,
}, null, 2));
