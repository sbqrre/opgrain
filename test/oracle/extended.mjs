import assert from "node:assert/strict";
import { runMoon } from "./bridge.mjs";
import { evaluate, wireResult } from "./oracle.mjs";

const seed = Number(process.env.EXTENDED_SEED ?? 20261122) >>> 0;
let state = seed;
const next = (limit) => {
  state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
  return state % limit;
};
const text = () => String.fromCharCode(...Array.from({ length: 2 + next(8) }, () => next(65536)));
const board = (count) => ({
  tasks: Array.from({ length: count }, (_, index) => ({
    id: "task-" + index, title: text(), points: index / 2,
    labels: ["review", "发布"], assigned: index % 2 === 0 ? null : "reviewer",
  })),
});
const branch = (original) => {
  const value = structuredClone(original);
  const list = value.tasks;
  if (list.length > 1) {
    const from = next(list.length);
    list.splice(next(list.length), 0, list.splice(from, 1)[0]);
  }
  if (list.length) {
    const item = list[next(list.length)];
    item.title = text();
    item.points += next(5) / 2;
  }
  if (list.length && next(2) === 0) list.splice(next(list.length), 1);
  list.splice(next(list.length + 1), 0, { id: "new-" + next(100000), title: text(), points: 0 });
  return value;
};

let total = 0;
for (let batch = 0; batch < 8; batch++) {
  const cases = Array.from({ length: 32 }, (_, index) => {
    const snapshot = board(2 + next(19));
    const afterLeft = branch(snapshot);
    const afterRight = branch(snapshot);
    return {
      label: `seed ${seed}, case ${batch * 32 + index}`,
      snapshot, afterLeft, afterRight,
      laterLeft: branch(afterLeft), laterRight: branch(afterRight),
    };
  });
  const requests = cases.flatMap(({ snapshot, afterLeft, afterRight, laterLeft, laterRight }) => [
    { command: "diff", snapshot, other: afterLeft, listIdentityKey: "id" },
    { command: "diff", snapshot, other: afterRight, listIdentityKey: "id" },
    { command: "diff", snapshot: afterLeft, other: laterLeft, listIdentityKey: "id" },
    { command: "diff", snapshot: afterRight, other: laterRight, listIdentityKey: "id" },
  ]);
  const diffs = runMoon(requests);
  const checks = [];
  const expectations = [];
  for (const [index, scenario] of cases.entries()) {
    const { snapshot, afterLeft, afterRight, label } = scenario;
    const [left, right, laterLeft, laterRight] = diffs.slice(index * 4, index * 4 + 4).map(result => result.value);
    try {
      assert.deepEqual(evaluate({ command: "apply", snapshot, op: left }), afterLeft);
      assert.deepEqual(evaluate({ command: "apply", snapshot, op: right }), afterRight);
      const inverse = evaluate({ command: "invert", op: left });
      assert.deepEqual(evaluate({ command: "apply", snapshot: afterLeft, op: inverse }), snapshot);
      const [a, b] = evaluate({ command: "transformX", op: left, other: right });
      const merged = evaluate({ command: "apply", snapshot: afterLeft, op: b });
      assert.deepEqual(evaluate({ command: "apply", snapshot: afterRight, op: a }), merged);
      const crossed = [right, laterRight];
      const leftBatches = [left, laterLeft].map(operation => {
        for (let j = 0; j < crossed.length; j++) {
          const pair = evaluate({ command: "transformX", op: operation, other: crossed[j] });
          operation = pair[0];
          crossed[j] = pair[1];
        }
        return operation;
      });
      const replay = (doc, operations) => operations.reduce(
        (snapshot, op) => evaluate({ command: "apply", snapshot, op }), doc,
      );
      const combined = replay(scenario.laterLeft, crossed);
      assert.deepEqual(replay(scenario.laterRight, leftBatches), combined);
      checks.push(
        { command: "applySnapshot", snapshot, op: left },
        { command: "applySnapshotVerified", snapshot, op: right },
        { command: "transformX", op: left, other: right },
        { command: "applySnapshotVerified", snapshot: afterLeft, op: inverse },
        { command: "mergeHistories", snapshot, left: [left], right: [right] },
        { command: "mergeHistories", snapshot, left: [left, laterLeft], right: [right, laterRight] },
      );
      expectations.push(
        wireResult(afterLeft), wireResult(afterRight), wireResult([a, b]),
        wireResult(snapshot), wireResult({ snapshot: merged, left: [a], right: [b] }),
        wireResult({ snapshot: combined, left: leftBatches, right: crossed }),
      );
    } catch (cause) {
      throw new Error(label + " " + JSON.stringify({ snapshot, left, right }), { cause });
    }
  }
  const actual = runMoon(checks);
  for (let index = 0; index < actual.length; index++) {
    assert.deepEqual(actual[index], expectations[index], cases[Math.floor(index / 6)].label);
  }
  total += cases.length;
}
console.log(`${total} identified-board branches passed differential snapshot, inverse and merge checks; seed ${seed}`);
