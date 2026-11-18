import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));

export function runMoon(requests) {
  const result = spawnSync("moon", ["run", "test/driver", "--target", "js", "--frozen", "--quiet"], {
    cwd: root,
    encoding: "utf8",
    input: JSON.stringify(requests),
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`MoonBit driver exited with status ${result.status}\n${result.stderr}`);
  }
  const responses = JSON.parse(result.stdout);
  if (!Array.isArray(responses) || responses.length !== requests.length) {
    throw new Error("MoonBit driver returned an invalid response batch");
  }
  return responses;
}
