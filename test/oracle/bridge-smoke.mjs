import assert from "node:assert/strict";
import { runMoon } from "./bridge.mjs";
import { evaluate } from "./oracle.mjs";

const card = { tasks: [{ title: "A😀" }, { title: "B" }] };
const left = [{ p: ["tasks", 0], lm: 1 }];
const right = [{ p: ["tasks", 0, "title", 1], sd: "\ud83d" }];
const requests = [
  { command: "apply", snapshot: card, op: right },
  { command: "transformX", op: left, other: right },
  { command: "invert", op: right },
  { command: "compose", op: right, other: [{ p: ["tasks", 0, "title", 1], si: "!" }] },
  { command: "normalize", op: { na: 1 } },
  { command: "apply", snapshot: null, op: [{ p: [], od: null }] },
  { command: "apply", op: [{ p: [], oi: null }] },
  { command: "transform", op: right, other: left, side: "right" },
];
const responses = runMoon(requests);
for (const [index, request] of requests.entries()) {
  const value = evaluate(request);
  const expected = value === undefined ? { present: false } : { present: true, value };
  assert.deepEqual(responses[index], expected, request.command);
}

const [leftPrime, rightPrime] = responses[1].value;
const leftDoc = evaluate({ command: "apply", snapshot: card, op: left });
const rightDoc = responses[0].value;
const receivedRight = evaluate({ command: "apply", snapshot: leftDoc, op: rightPrime });
const receivedLeft = runMoon([{ command: "apply", snapshot: rightDoc, op: leftPrime }])[0];
assert.deepEqual(receivedLeft, { present: true, value: receivedRight });
assert.equal(receivedRight.tasks[1].title, "A\ude00");
console.log(`${requests.length} interoperability requests passed; verified both directions with surrogate-splitting text`);
