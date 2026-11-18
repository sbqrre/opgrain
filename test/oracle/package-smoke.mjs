import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));
const fixture = mkdtempSync(join(tmpdir(), "opgrain-package-"));

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${command} exited with status ${result.status}\n${result.stdout}\n${result.stderr}`);
  }
  return result.stdout;
}

const target = join(fixture, "build");
run("moon", ["package", "--frozen", "--target-dir", target], root);
const artifacts = join(target, "publish");
const archives = readdirSync(artifacts).filter((file) => /\.zip$/.test(file));
assert.equal(archives.length, 1, "expected exactly one published module archive");
const archive = resolve(artifacts, archives[0]);

const isWindows = process.platform === "win32";
const entries = run(isWindows ? "tar" : "unzip", isWindows ? ["-tf", archive] : ["-Z1", archive], fixture)
  .trim().split(/\r?\n/).map((entry) => entry.replaceAll("\\", "/"));
assert.ok(entries.every((entry) => !entry.startsWith("/") && !entry.split("/").includes("..")));
assert.ok(entries.includes("moon.mod") && entries.includes("LICENSE") && entries.includes("README.md"));
assert.ok(entries.every((entry) => !/^(test\/|\.github\/)|_(wb)?test\.mbt$/.test(entry)));

const library = join(fixture, "opgrain");
const consumer = join(fixture, "app");
mkdirSync(library);
mkdirSync(consumer);
if (isWindows) run("tar", ["-xf", archive, "-C", library], fixture);
else run("unzip", ["-q", archive, "-d", library], fixture);

const version = archives[0].match(/^sbqrre-opgrain-(.+)\.zip$/)?.[1];
assert.ok(version, "expected the archive for sbqrre/opgrain");
writeFileSync(join(fixture, "moon.work"), 'members = ["opgrain", "app"]\n');
writeFileSync(join(consumer, "moon.mod"), `name = "local/package-smoke"\nversion = "0.1.0"\nimport { "sbqrre/opgrain@${version}" }\n`);
writeFileSync(join(consumer, "moon.pkg"), 'import { "sbqrre/opgrain" }\npkgtype(kind: "executable")\n');
writeFileSync(join(consumer, "main.mbt"), String.raw`
fn main {
  let base = @opgrain.parse_json("{\"tasks\":[\"Review\"]}") catch { _ => abort("snapshot") }
  let left = @opgrain.Operation::parse("[{\"p\":[\"tasks\",0],\"li\":\"Test\"}]") catch { _ => abort("left") }
  let right = @opgrain.Operation::parse("[{\"p\":[\"tasks\",0],\"li\":\"Publish\"}]") catch { _ => abort("right") }
  let (_, after_left) = @opgrain.transform_x(left, right) catch { _ => abort("transform") }
  let merged = @opgrain.apply(@opgrain.apply(base, left), after_left) catch { _ => abort("apply") }
  println(@opgrain.stringify_json(merged) catch { _ => abort("stringify") })
}
`);

const result = run("moon", ["run", ".", "--target", "js", "--frozen", "--quiet"], consumer);
assert.deepEqual(JSON.parse(result), { tasks: ["Test", "Publish", "Review"] });
console.log(`Validated ${archives[0]} from an independent MoonBit module`);
