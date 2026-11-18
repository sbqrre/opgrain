import assert from "node:assert/strict";
import test from "node:test";
import { reduceExchange } from "./reduce.mjs";
import { evaluate } from "./oracle.mjs";

test("delta reduction keeps a discrepancy and its applicable path", () => {
  const input = {
    request: {
      command: "apply", snapshot: { a: 1, b: 2, irrelevant: [3] },
      op: [{ p: ["b"], na: 4 }, { p: ["a"], na: 2 }, { p: [], oi: { final: 5 } }],
    },
  };
  const frozen = structuredClone(input);
  const minimized = reduceExchange(input, (request) => {
    const value = evaluate(request);
    if (request.op.some(({ p }) => p[0] === "a")) {
      return { error: "InvalidPath" };
    }
    return { present: true, value };
  });
  assert.deepEqual(minimized.request, {
    command: "apply", snapshot: { a: 1 }, op: [{ p: ["a"], na: 2 }],
  });
  assert.equal(minimized.kind, "MoonBit:InvalidPath");
  assert.deepEqual(input, frozen);
});

test("semantic prerequisites prevent a transformed mismatch from shrinking to an invalid pair", () => {
  const input = {
    snapshot: { title: "abc", optional: 0 },
    request: {
      command: "transformX",
      op: [{ p: ["title", 0], sd: "a" }],
      other: [{ p: ["title", 1], si: "!" }],
    },
  };
  const minimized = reduceExchange(input, (request) => {
    const value = evaluate(request);
    if (request.op.length && request.other.length) {
      return { present: true, value: [[], []] };
    }
    return { present: true, value };
  });
  assert.deepEqual(minimized.snapshot, { title: "abc" });
  assert.deepEqual(minimized.request, input.request);
  assert.equal(minimized.kind, "wire mismatch");
});
