import { readFileSync } from "node:fs";
import { isDeepStrictEqual } from "node:util";
import { pathToFileURL } from "node:url";
import { runMoon } from "./bridge.mjs";
import { evaluate, wireResult } from "./oracle.mjs";

function apply(snapshot, op) {
  return evaluate({ command: "apply", snapshot, op });
}

function referenceOutcome({ snapshot, request }) {
  const expected = evaluate(request);
  const base = request.command === "apply" ? request.snapshot : snapshot;
  switch (request.command) {
    case "compose":
      apply(apply(base, request.op), request.other);
      apply(base, expected);
      break;
    case "invert":
      apply(apply(base, request.op), expected);
      break;
    case "transform":
      apply(base, request.op);
      apply(apply(base, request.other), expected);
      break;
    case "transformX":
      apply(apply(base, request.op), expected[1]);
      apply(apply(base, request.other), expected[0]);
      break;
    case "normalize":
      apply(base, expected);
      break;
  }
  return wireResult(expected);
}

function failureKind(actual, expected) {
  if (isDeepStrictEqual(actual, expected)) return null;
  if (actual?.error) return `MoonBit:${actual.error.split("(")[0]}`;
  return "wire mismatch";
}

export function reduceExchange(input, observe = (request) => runMoon([request])[0]) {
  let current = structuredClone(input);
  let probes = 0;
  function compare(candidate) {
    let expected;
    try {
      expected = referenceOutcome(candidate);
    } catch {
      return null;
    }
    probes++;
    const actual = observe(candidate.request);
    return { actual, expected, kind: failureKind(actual, expected) };
  }
  let outcome = compare(current);
  if (!outcome?.kind) throw new Error("The input must demonstrate a discrepancy on an applicable upstream operation");
  const kind = outcome.kind;
  function accept(candidate) {
    const next = compare(candidate);
    if (next?.kind !== kind) return false;
    outcome = next;
    current = candidate;
    return true;
  }

  let changed;
  do {
    changed = false;
    for (const key of ["op", "other"]) {
      let operation = current.request[key];
      if (!Array.isArray(operation)) continue;
      for (let size = Math.ceil(operation.length / 2); size > 0; size = Math.floor(size / 2)) {
        for (let start = 0; start + size <= operation.length;) {
          const shorter = [...operation.slice(0, start), ...operation.slice(start + size)];
          if (accept({ ...current, request: { ...current.request, [key]: shorter } })) {
            operation = shorter;
            changed = true;
          } else {
            start++;
          }
        }
      }
    }

    const isApply = current.request.command === "apply";
    const snapshot = isApply ? current.request.snapshot : current.snapshot;
    if (snapshot && typeof snapshot === "object" && !Array.isArray(snapshot)) {
      for (const key of Object.keys(snapshot)) {
        const remaining = { ...(isApply ? current.request.snapshot : current.snapshot) };
        delete remaining[key];
        const candidate = isApply
          ? { ...current, request: { ...current.request, snapshot: remaining } }
          : { ...current, snapshot: remaining };
        changed = accept(candidate) || changed;
      }
    }
  } while (changed);
  return { snapshot: current.snapshot, request: current.request, ...outcome, probes };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const input = JSON.parse(readFileSync(0, "utf8"));
  console.log(JSON.stringify(reduceExchange(input), null, 2));
}
