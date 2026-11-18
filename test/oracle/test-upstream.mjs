import { spawnSync } from "node:child_process";
import { mkdtempSync, rmdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";

const require = createRequire(import.meta.url);
const packageRoot = dirname(require.resolve("ot-json0/package.json"));
const mocha = join(dirname(require.resolve("mocha/package.json")), "bin", "_mocha");
const cwd = mkdtempSync(join(tmpdir(), "opgrain-upstream-"));
const result = spawnSync(
  process.execPath,
  [mocha, "--no-config", "--no-package", "--require",
    require.resolve("coffee-script/register"), "--reporter", "dot",
    join(packageRoot, "test", "*.coffee")],
  {
    cwd,
    stdio: "inherit",
    env: { ...process.env, SEED: process.env.SEED ?? "1", SYNCFILE: "fuzzercrash.data" },
  },
);
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;

if (process.exitCode === 0) rmdirSync(cwd);
else console.error("Upstream test state was retained in", cwd);
