import assert from "node:assert/strict";
import { runMoon } from "./bridge.mjs";
import { evaluate, wireResult } from "./oracle.mjs";

const card = { tasks: [{ title: "A😀" }, { title: "B" }] };
const left = [{ p: ["tasks", 0], lm: 1 }];
const right = [{ p: ["tasks", 0, "title", 1], sd: "\ud83d" }];
const requests = [
  { command: "apply", snapshot: card, op: right },
  { command: "transformX", op: left, other: right },
  { command: "invert", op: right },
  { command: "invert", op: [{ p: [], na: 0 }] },
  { command: "compose", op: right, other: [{ p: ["tasks", 0, "title", 1], si: "!" }] },
  { command: "normalize", op: { na: 1 } },
  { command: "apply", snapshot: null, op: [{ p: [], od: null }] },
  { command: "apply", op: [{ p: [], oi: null }] },
  { command: "transform", op: right, other: left, side: "right" },
];
const responses = runMoon(requests);
for (const [index, request] of requests.entries()) {
  assert.deepEqual(responses[index], wireResult(evaluate(request)), request.command);
}

const [leftPrime, rightPrime] = responses[1].value;
const leftDoc = evaluate({ command: "apply", snapshot: card, op: left });
const rightDoc = responses[0].value;
const receivedRight = evaluate({ command: "apply", snapshot: leftDoc, op: rightPrime });
const receivedLeft = runMoon([{ command: "apply", snapshot: rightDoc, op: leftPrime }])[0];
assert.deepEqual(receivedLeft, { present: true, value: receivedRight });
assert.equal(receivedRight.tasks[1].title, "A\ude00");
console.log(`${requests.length} interoperability requests passed; verified both directions with surrogate-splitting text`);

const drafts = [
  {
    before: { tasks: [{ id: "a", title: "待😀办" }, { id: "b", title: "复查" }] },
    after: { tasks: [{ id: "b", title: "复查" }, { id: "a", title: "待\ud83d!办" }] },
    listIdentityKey: "id",
  },
  {
    before: { tasks: [null, ["A", false], "打包"], cleared: 1 },
    after: { tasks: [["A", true], "打包", "发版"], assigned: null },
  },
  { before: undefined, after: null },
  { before: null, after: undefined },
];
const diffResponses = runMoon(drafts.map(({ before, after, listIdentityKey }) => ({
  command: "diff", snapshot: before, other: after, listIdentityKey,
})));
const inverseRequests = [];
const applications = [];
for (const [index, { before, after }] of drafts.entries()) {
  const { present, value: op } = diffResponses[index];
  assert.equal(present, true, JSON.stringify(diffResponses[index]));
  assert.deepEqual(evaluate({ command: "apply", snapshot: before, op }), after);
  inverseRequests.push({ command: "invert", op });
  applications.push({ command: "apply", snapshot: after, op: evaluate({ command: "invert", op }) });
}
const inverseResponses = runMoon(inverseRequests);
const applyResponses = runMoon(applications);
for (const [index, { before, after }] of drafts.entries()) {
  assert.deepEqual(evaluate({
    command: "apply", snapshot: after, op: inverseResponses[index].value,
  }), before);
  assert.deepEqual(applyResponses[index], wireResult(before));
}
console.log("4 generated snapshot deltas passed cross-runtime apply and inverse checks");
