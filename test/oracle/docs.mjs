import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));
const documents = ["README.md", "CHANGELOG.md", "THIRD_PARTY_NOTICES.md",
  ...readdirSync(resolve(root, "docs")).filter(name => name.endsWith(".md")).map(name => "docs/" + name)];
let links = 0;
for (const path of documents) {
  const source = readFileSync(resolve(root, path), "utf8").replaceAll("\r\n", "\n");
  const prose = source.replace(/^```[^\n]*\n[\s\S]*?^```\s*$/gm, "");
  for (const match of prose.matchAll(/\[[^\]\n]*\]\(([^)\n]+)\)/g)) {
    const target = match[1].trim();
    if (/^[a-z][a-z\d+.-]*:/i.test(target) || target.startsWith("#")) continue;
    const location = decodeURIComponent(target.split("#")[0]);
    const file = resolve(root, dirname(path), location);
    const within = relative(root, file);
    assert.ok(within !== ".." && !within.startsWith("../") && !within.startsWith("..\\") && !isAbsolute(within),
      path + ": local link leaves repository: " + target);
    assert.ok(existsSync(file), path + ": missing local link: " + target);
    links++;
  }
}
const readme = readFileSync(resolve(root, "README.md"), "utf8").replaceAll("\r\n", "\n");
const quickstart = readFileSync(resolve(root, "examples/quickstart/main.mbt"), "utf8").replaceAll("\r\n", "\n").trim();
const snippets = [...readme.matchAll(/^```moonbit\n([\s\S]*?)^```/gm)].map(match => match[1].trim());
assert.ok(snippets.includes(quickstart), "README runnable program diverges from examples/quickstart");
const imports = readFileSync(resolve(root, "examples/quickstart/moon.pkg"), "utf8").replaceAll("\r\n", "\n").trim();
assert.ok(snippets.includes(imports), "README package imports diverge from examples/quickstart");
const version = readFileSync(resolve(root, "moon.mod"), "utf8").match(/version\s*=\s*"([^"]+)"/)?.[1];
assert.ok(version, "manifest version is missing");
assert.ok(readme.includes("moon add sbqrre/opgrain@" + version), "README install version differs from manifest");
assert.ok(readme.includes("moon run cmd/main --target js"), "README run command is missing");
console.log(JSON.stringify({ documents: documents.length, localLinks: links, quickstart: "matches README", version }));
