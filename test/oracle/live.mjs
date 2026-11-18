import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runMoon } from "./bridge.mjs";
import { evaluate, json0 } from "./oracle.mjs";

const seed = process.env.SEED ?? "opgrain-live-1";
process.env.SEED = seed;
process.env.SYNCFILE = join(mkdtempSync(join(tmpdir(), "opgrain-live-")), "state.json");
const require = createRequire(import.meta.url);
require("coffee-script/register");
const upstreamRequire = createRequire(require.resolve("ot-json0/package.json"));
const generateJson = upstreamRequire("./test/json0-generator.coffee");
const generateText = upstreamRequire("./test/text0-generator.coffee");

const board = {
  tasks: [{ title: "右端 😀 e\u0301", points: 2 }, { title: "左端", points: 5 }],
  backlog: [],
};
const rootText = (snapshot) => {
  const [text, updated] = generateText(snapshot);
  return [[{ p: [], t: "text0", o: text }], updated];
};

function requestValue(request) {
  const value = evaluate(request);
  return value === undefined
    ? { present: false }
    : { present: true, value: JSON.parse(JSON.stringify(value)) };
}

function compareBatch(cases, requests) {
  const actual = runMoon(requests.map(({ request }) => request));
  for (let i = 0; i < requests.length; i++) {
    const { request, label, scenario } = requests[i];
    try {
      assert.deepEqual(actual[i], requestValue(request));
    } catch (cause) {
      throw new Error(`${label} failed with seed ${seed}: ${JSON.stringify({
        scenario: cases[scenario].label, snapshot: cases[scenario].snapshot,
        request, observed: actual[i],
      })}`, { cause });
    }
  }
  return actual.map((entry) => entry.value);
}

function runCases(cases) {
  const primary = cases.flatMap(({ label, snapshot, left, right, later }, scenario) =>
    [
      { command: "apply", snapshot, op: left },
      { command: "apply", snapshot, op: right },
      { command: "compose", op: left, other: later },
      { command: "invert", op: left },
      { command: "transformX", op: left, other: right },
      { command: "transform", op: left, other: right, side: "left" },
      { command: "transform", op: right, other: left, side: "right" },
    ].map((request) => ({ request, label: `${label} ${request.command}`, scenario })),
  );
  const outputs = compareBatch(cases, primary);
  const semantic = cases.flatMap(({ label, snapshot, left, right, later, afterLeft, afterRight, afterLater }, scenario) => {
    const [leftDoc, rightDoc, combined, inverse, [moonLeft, moonRight]] =
      outputs.slice(scenario * 7, scenario * 7 + 7);
    const jsRight = evaluate({ command: "transform", op: right, other: left, side: "right" });

    const jsLeftThenRight = evaluate({ command: "apply", snapshot: leftDoc, op: moonRight });
    const jsRightThenLeft = evaluate({ command: "apply", snapshot: rightDoc, op: moonLeft });
    assert.deepEqual(leftDoc, afterLeft, label);
    assert.deepEqual(rightDoc, afterRight, label);
    assert.deepEqual(jsRightThenLeft, jsLeftThenRight, label);
    assert.deepEqual(evaluate({ command: "apply", snapshot: afterLeft, op: later }), afterLater, label);
    assert.deepEqual(evaluate({ command: "apply", snapshot, op: combined }), afterLater, label);
    assert.deepEqual(evaluate({ command: "apply", snapshot: leftDoc, op: inverse }), snapshot, label);

    return [
      { command: "apply", snapshot: rightDoc, op: moonLeft },
      { command: "apply", snapshot: leftDoc, op: jsRight },
      { command: "apply", snapshot, op: combined },
      { command: "apply", snapshot: leftDoc, op: inverse },
    ].map((request) => ({ request, label: `${label} rewritten operation`, scenario }));
  });
  compareBatch(cases, semantic);
}

for (const { label, generate, initial, total } of [
  { label: "legacy", generate: generateJson, initial: board, total: 1000 },
  { label: "subtype", generate: generateJson, initial: board, total: 1000 },
  { label: "root-text0", generate: rootText, initial: board.tasks[0].title, total: 2000 },
]) {
  if (label === "subtype") json0._testStringSubtype = true;
  let pending = [];
  let snapshot = initial;
  try {
    for (let index = 0; index < total; index++) {
      if (index % 5 === 0) snapshot = initial;
      const [left, afterLeft] = generate(structuredClone(snapshot));
      const [right, afterRight] = generate(structuredClone(snapshot));
      const [later, afterLater] = generate(structuredClone(afterLeft));
      pending.push({
        label: `${label} #${index}`, snapshot, left, right, later, afterLeft, afterRight, afterLater,
      });
      snapshot = afterLeft;
      if (pending.length === 250 || index + 1 === total) {
        runCases(pending);
        pending = [];
      }
    }
  } finally {
    delete json0._testStringSubtype;
  }
  console.log(`${label}: ${total} live cases passed, seed ${seed}`);
}
