import { spawnSync } from "node:child_process";
import { cpus, platform, release } from "node:os";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const targets = process.argv.slice(2);
if (!targets.length) targets.push("native", "js", "wasm", "wasm-gc");
if (targets.some(target => !["native", "js", "wasm", "wasm-gc"].includes(target))) {
  throw new Error("Targets must be native, js, wasm or wasm-gc");
}
const execute = (args) => {
  const result = spawnSync("moon", args, { cwd: root, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim();
};
const environment = {
  os: platform(), osRelease: release(), cpu: cpus()[0]?.model,
  node: process.version, toolchain: execute(["version", "--all"]),
  mode: "release", warmups: 3, samples: 9,
};
const runs = [];
for (const target of targets) {
  for (const workload of ["benchmarks", "benchmarks/persistent"]) {
    runs.push({
      target, workload,
      results: JSON.parse(execute(["run", workload, "--target", target, "--release", "--frozen", "--quiet"])),
    });
  }
}
console.log(JSON.stringify({ environment, runs }, null, 2));
