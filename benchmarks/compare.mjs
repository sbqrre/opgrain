import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, copyFileSync } from "node:fs";
import { cpus, platform, release, tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const reference = "b265a148628b096c29e0e0b3547e6f230c43f04e";
const targets = process.argv.slice(2);
if (!targets.length) targets.push("native", "js", "wasm", "wasm-gc");
if (targets.some(target => !["native", "js", "wasm", "wasm-gc"].includes(target))) {
  throw new Error("Targets must be native, js, wasm or wasm-gc");
}
const run = (command, args, cwd) => {
  const result = spawnSync(command, args, { cwd, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim();
};
const baseline = mkdtempSync(join(tmpdir(), "opgrain-baseline-"));
const archive = join(baseline, "source.zip");
run("git", ["archive", "--format=zip", "--output=" + archive, reference], root);
if (platform() === "win32") run("tar", ["-xf", archive, "-C", baseline], root);
else run("unzip", ["-q", archive, "-d", baseline], root);
mkdirSync(join(baseline, "benchmarks"));
for (const name of ["main.mbt", "moon.pkg"]) {
  copyFileSync(join(root, "benchmarks", name), join(baseline, "benchmarks", name));
}
const runs = [];
for (const target of targets) {
  const args = ["run", "benchmarks", "--target", target, "--release", "--frozen", "--quiet"];
  const before = JSON.parse(run("moon", args, baseline));
  const after = JSON.parse(run("moon", args, root));
  runs.push({
    target, before, after,
    ratios: before.map(previous => {
      const current = after.find(result => result.name === previous.name);
      if (!current) throw new Error("Missing workload " + previous.name);
      return { name: previous.name, beforeMedianUs: previous.median, afterMedianUs: current.median, beforeOverAfter: previous.median / current.median };
    }),
  });
}
console.log(JSON.stringify({
  environment: { os: platform(), osRelease: release(), cpu: cpus()[0]?.model, node: process.version, toolchain: run("moon", ["version", "--all"], root) },
  reference, runs,
}, null, 2));
