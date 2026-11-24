import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));
const fixture = mkdtempSync(join(tmpdir(), "opgrain-package-"));
const registry = process.argv.includes("--registry");
const version = readFileSync(join(root, "moon.mod"), "utf8").match(/version\s*=\s*"([^"]+)"/)?.[1];
assert.ok(version, "expected a module version");

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with status ${result.status}\n${result.stdout}\n${result.stderr}`);
  return result.stdout;
}

if (!registry) {
  const target = join(fixture, "build");
  run("moon", ["package", "--frozen", "--target-dir", target], root);
  const artifacts = join(target, "publish");
  const archives = readdirSync(artifacts).filter(file => /\.zip$/.test(file));
  assert.deepEqual(archives, [`sbqrre-opgrain-${version}.zip`]);
  const archive = resolve(artifacts, archives[0]);
  const windows = process.platform === "win32";
  const entries = run(windows ? "tar" : "unzip", windows ? ["-tf", archive] : ["-Z1", archive], fixture)
    .trim().split(/\r?\n/).map(entry => entry.replaceAll("\\", "/"));
  assert.ok(entries.every(entry => !entry.startsWith("/") && !entry.split("/").includes("..")));
  assert.ok(["moon.mod", "LICENSE", "README.md", "THIRD_PARTY_NOTICES.md", "snapshot.mbt", "undo.mbt", "indexed_diff.mbt", "decoder.mbt", "rebase_buffer.mbt", "LICENSES/ot-json0-1.1.0.txt", "LICENSES/ot-fuzzer-1.3.1.txt", "docs/provenance.md"].every(name => entries.includes(name)));
  assert.ok(entries.every(entry => !/^(test\/|benchmarks\/|\.github\/)|_(wb)?test\.mbt$/.test(entry)));
  const library = join(fixture, "opgrain");
  mkdirSync(library);
  if (windows) run("tar", ["-xf", archive, "-C", library], fixture);
  else run("unzip", ["-q", archive, "-d", library], fixture);
  for (const [name, version] of [["ot-json0", "1.1.0"], ["ot-fuzzer", "1.3.1"]]) {
    const source = readFileSync(join(root, "test/oracle/node_modules", name, "README.md"), "utf8");
    const notice = source.slice(source.indexOf("Copyright 2011")).trim();
    assert.equal(readFileSync(join(library, "LICENSES", name + "-" + version + ".txt"), "utf8").trim(), notice);
  }
  writeFileSync(join(fixture, "moon.work"), 'members = ["opgrain", "app", "quickstart"]\n');
}

const consumer = join(fixture, "app");
mkdirSync(consumer);
writeFileSync(join(consumer, "moon.mod"), `name = "sbqrre/opgrain-consumer-check"\nversion = "0.1.0"\nimport { "sbqrre/opgrain@${version}" }\n`);
writeFileSync(join(consumer, "moon.pkg"), 'import { "sbqrre/opgrain" }\npkgtype(kind: "executable")\n');
writeFileSync(join(consumer, "main.mbt"), String.raw`
fn main {
  try {
    let engine = @opgrain.Engine::new()
    let indexed = engine.diff_keyed_list(
      [{ "id": "a" }, { "id": "b" }],
      [{ "id": "b" }, { "id": "a" }], "id",
    )
    guard indexed.metrics().moved == 1 else { abort("indexed list diff") }
    let text = @opgrain.diff_text("Review😀", "Ready😀").operation()
    guard text.apply("Review😀") == "Ready😀" else { abort("UTF16 diff") }
    let decoded = @opgrain.decode_json(@opgrain.encode_json(Json::string("Review😀")))
    guard decoded == Json::string("Review😀") else { abort("bounded codec") }
    let base = @opgrain.parse_json("{\"tasks\":[\"Review\"]}")
    let left = @opgrain.Operation::parse("[{\"p\":[\"tasks\",0],\"li\":\"Test\"}]")
    let right = @opgrain.Operation::parse("[{\"p\":[\"tasks\",0],\"li\":\"Publish\"}]")
    let (_, after_left) = engine.transform_x(left, right)
    let merged = engine.apply(engine.apply(base, left), after_left)
    let handle = @opgrain.Snapshot::new(Some(merged))
    let draft = engine.draft_snapshot(handle)
    ignore(draft.transaction(candidate => {
      candidate.splice_items([Key("tasks")], 1, 1, [Json::string("Ready")])
    }))
    let journal = engine.journal_snapshot(handle)
    ignore(journal.append(draft.operation()))
    journal.compact(1)
    guard journal.oldest_revision() == 1 && handle.to_json() == Some(merged) else { abort("checkpoint") }
    let tiny = @opgrain.Snapshot::new(Some(Json::number(1.0e-20)))
    let addition = @opgrain.Operation::parse("[{\"p\":[],\"na\":1}]")
    let edit = engine.prepare_edit(tiny, addition)
    guard engine.apply_snapshot_verified(edit.snapshot(), edit.inverse()).to_json() == tiny.to_json() else { abort("numeric undo") }
    println(@opgrain.stringify_json(journal.snapshot().unwrap()))
  } catch { _ => abort("consumer validation failed") }
}
`);
if (registry) run("moon", ["check", "--target", "js"], consumer);
const quickstart = join(fixture, "quickstart");
mkdirSync(join(quickstart, "cmd/main"), { recursive: true });
writeFileSync(join(quickstart, "moon.mod"), `name = "sbqrre/opgrain-readme-check"\nversion = "0.1.0"\nimport { "sbqrre/opgrain@${version}" }\n`);
writeFileSync(join(quickstart, "cmd/main/moon.pkg"), readFileSync(join(root, "examples/quickstart/moon.pkg")));
writeFileSync(join(quickstart, "cmd/main/main.mbt"), readFileSync(join(root, "examples/quickstart/main.mbt")));
if (registry) run("moon", ["check", "--target", "js"], quickstart);
for (const target of ["js", "native", "wasm", "wasm-gc"]) {
  const result = run("moon", ["run", ".", "--target", target, "--frozen", "--quiet"], consumer);
  assert.deepEqual(JSON.parse(result), { tasks: ["Test", "Ready", "Review"] });
  const sample = run("moon", ["run", "cmd/main", "--target", target, "--frozen", "--quiet"], quickstart);
  assert.deepEqual(JSON.parse(sample), { tasks: ["Review", "Publish"] });
}
console.log(`Validated sbqrre/opgrain@${version} from ${registry ? "the public registry" : "its packaged archive"} in four targets`);
