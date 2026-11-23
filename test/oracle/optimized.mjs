
import assert from "node:assert/strict";
import { writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runMoon } from "./bridge.mjs";
import { evaluate, wireResult } from "./oracle.mjs";

const seed = Number(process.env.OPTIMIZED_SEED ?? 20261123) >>> 0;
let state = seed;
const next = limit => {
  state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
  return state % limit;
};
const text = () => String.fromCharCode(...Array.from({ length: next(30) }, () =>
  [10, 13, 97, 98, 99, 0x4e2d, 0xd800 + next(2048), next(65536)][next(8)]));
const list = n => Array.from({ length: n }, (_, id) => ({ id: String(id), points: id / 2, title: text() }));
const changed = before => {
  const after = structuredClone(before).filter(() => next(4) !== 0);
  for (let i = 0; i < 3; i++) after.splice(next(after.length + 1), 0, { id: "new-" + i, points: next(8) / 2, title: text() });
  for (let i = after.length - 1; i > 0; i--) {
    const j = next(i + 1);
    [after[i], after[j]] = [after[j], after[i]];
  }
  if (after.length) after[next(after.length)].title = text();
  return after;
};

let scenarios = 0;
let comparisons = 0;
for (let batch = 0; batch < 8; batch++) {
  const cases = Array.from({ length: 32 }, () => {
    const before = list(next(25));
    return { before, after: changed(before), left: text(), right: text() };
  });
  const requests = cases.flatMap(c => [
    { command: "keyedDiff", snapshot: c.before, other: c.after },
    { command: "snapshotDiff", snapshot: { tasks: c.before }, other: { tasks: c.after } },
    { command: "textDiff", snapshot: c.left, other: c.right },
    { command: "lineDiff", snapshot: c.left, other: c.right },
    { command: "codec", snapshot: { tasks: c.before, text: c.left, numbers: [0, -0, 0.1, Number.MIN_VALUE, Number.MAX_VALUE, 9007199254740992] } },
  ]);
  try {
    const results = runMoon(requests);
    const checks = [];
    const expected = [];
    for (const [index, c] of cases.entries()) {
      const outputs = results.slice(index * 5, index * 5 + 5);
      for (const output of outputs) assert.equal(output.error, undefined);
      const pairs = [
        [c.before, c.after],
        [{ tasks: c.before }, { tasks: c.after }],
        [c.left, c.right],
        [c.left, c.right],
      ];
      for (let kind = 0; kind < 4; kind++) {
        const [before, after] = pairs[kind];
        const op = outputs[kind].value;
        assert.deepEqual(evaluate({ command: "apply", snapshot: before, op }), after);
        const inverse = evaluate({ command: "invert", op });
        assert.deepEqual(evaluate({ command: "apply", snapshot: after, op: inverse }), before);
        checks.push(
          { command: "applySnapshotVerified", snapshot: before, op },
          { command: "invert", op },
          { command: "normalize", op },
        );
        expected.push(wireResult(after), wireResult(inverse), wireResult(evaluate({ command: "normalize", op })));
        comparisons += 5;
      }
      assert.deepEqual(outputs[4], wireResult(requests[index * 5 + 4].snapshot));
      comparisons++;
      scenarios++;
    }
    assert.deepEqual(runMoon(checks), expected);
  } catch (error) {
    const path = join(tmpdir(), "opgrain-optimized-failure-" + seed + "-" + batch + ".json");
    writeFileSync(path, JSON.stringify({ seed, batch, requests }, null, 2) + "\n");
    throw new Error("seed " + seed + ", batch " + batch + ", reproduction " + path, { cause: error });
  }
}
console.log(JSON.stringify({ seed, scenarios, comparisons, generators: ["keyedDiff", "snapshotDiff", "textDiff", "lineDiff"], codec: true }));
