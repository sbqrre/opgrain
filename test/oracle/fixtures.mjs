import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import Mocha from "mocha";

const require = createRequire(import.meta.url);
const upstream = dirname(require.resolve("ot-json0/package.json"));
const requireUpstream = createRequire(join(upstream, "package.json"));
const seed = "opgrain-20261118";
process.env.SEED = seed;
process.env.SYNCFILE = join(mkdtempSync(join(tmpdir(), "opgrain-fixtures-")), "seedstate.json");
require("coffee-script/register");
const json0 = requireUpstream("./lib/json0");
const text0 = requireUpstream("./lib/text0");

function withTypedPath(component, objectPaths) {
  const path = component.p.map((segment, index, original) =>
    objectPaths.some((keyPath) =>
      keyPath.length === index + 1 && keyPath.every((key, i) => key === original[i]))
      ? String(segment)
      : segment,
  );
  const end = path.at(-1);
  const listOrText = ["li", "ld", "lm", "si", "sd"].some((key) => key in component);
  const object = "oi" in component || "od" in component;
  if (listOrText && typeof end !== "number") {
    return { ...component, p: [...path.slice(0, -1), 0] };
  }
  if (object && path.length > 0 && typeof end !== "string") {
    return { ...component, p: [...path.slice(0, -1), String(end)] };
  }
  return path.some((key, index) => key !== component.p[index]) ? { ...component, p: path } : component;
}

async function captureTests() {
  const records = [];
  const restore = [];
  let test = "";
  let depth = 0;
  for (const [family, type, methods] of [
    ["json0", json0, ["create", "apply", "compose", "invert", "normalize", "transform", "transformX"]],
    ["text0", text0, ["apply", "compose", "invert", "normalize", "transform", "transformX", "transformCursor"]],
  ]) {
    for (const name of methods) {
      const original = type[name];
      restore.push(() => { type[name] = original; });
      type[name] = function (...args) {
        const outer = depth++ === 0;
        const input = outer ? structuredClone(args) : null;
        try {
          const value = original.apply(this, args);
          if (outer) {
            const record = [family, test, name, input, structuredClone(value ?? null)];
            records.push(record);
            if (family === "json0" && name === "transform") {
              const [left, right, side] = input;
              const objectPaths = [...left, ...right]
                .filter((c) => ("oi" in c || "od" in c) && typeof c.p.at(-1) === "number")
                .map((c) => c.p);
              const typedLeft = left.map((c) => withTypedPath(c, objectPaths));
              const typedRight = right.map((c) => withTypedPath(c, objectPaths));
              if (typedLeft.some((c, i) => c !== left[i]) || typedRight.some((c, i) => c !== right[i])) {
                // Keep the original synthetic probe and exercise its typed counterpart.
                record.push("InvalidComponent");
                const typed = [typedLeft, typedRight, side];
                records.push([family, test, name, typed, structuredClone(original.apply(this, typed))]);
              }
            }
          }
          return value;
        } finally {
          depth--;
        }
      };
    }
  }
  const mocha = new Mocha({ reporter: "dot", grep: /randomizer/, invert: true });
  mocha.addFile(join(upstream, "test", "json0.coffee"));
  mocha.addFile(join(upstream, "test", "text0.coffee"));
  try {
    const result = await new Promise((resolve) => {
      const runner = mocha.run(resolve);
      runner.on("test", (current) => { test = current.fullTitle(); });
    });
    assert.equal(result, 0);
    assert.equal(new Set(records.map((record) => record[1])).size, 63);
    assert.equal(records.filter((record) => record.length === 6).length, 12);
  } finally {
    for (const undo of restore) undo();
  }
  return records;
}

const board = {
  tasks: [
    { title: "Review 中😀e\u0301", points: 2 },
    { title: "Publish", points: 5 },
  ],
  backlog: [],
  status: "ready",
};

function propertyCases() {
  const genJson = requireUpstream("./test/json0-generator.coffee");
  const genText = requireUpstream("./test/text0-generator.coffee");
  const cases = [];
  for (const [family, type, generator, initial] of [
    ["legacy", json0, genJson, board],
    ["subtype", json0, genJson, board],
    ["text0", text0, genText, board.tasks[0].title],
  ]) {
    if (family === "subtype") json0._testStringSubtype = true;
    let snapshot = initial;
    for (let index = 0; index < 160; index++) {
      if (index % 5 === 0) snapshot = initial;
      const [left, leftResult] = generator(structuredClone(snapshot));
      const [right, rightResult] = generator(structuredClone(snapshot));
      const [second, secondResult] = generator(structuredClone(leftResult));
      const [third, finalResult] = generator(structuredClone(secondResult));
      const [rightSecond, rightFinal] = generator(structuredClone(rightResult));
      const [leftPrime, rightPrime] = type.transformX(left, right);
      const lr = type.apply(structuredClone(leftResult), rightPrime);
      const rl = type.apply(structuredClone(rightResult), leftPrime);
      const compose = type.compose(left, second);
      assert.deepEqual(type.apply(structuredClone(snapshot), left), leftResult);
      assert.deepEqual(type.apply(structuredClone(snapshot), compose), secondResult);
      assert.deepEqual(type.apply(structuredClone(leftResult), type.invert(left)), snapshot);
      assert.deepEqual(lr, rl);
      const rightHistory = [right, rightSecond];
      const leftHistory = [left, second, third].map((leftOp) => {
        for (let i = 0; i < rightHistory.length; i++) {
          const rightOp = rightHistory[i];
          rightHistory[i] = type.transform(rightOp, leftOp, "right");
          leftOp = type.transform(leftOp, rightOp, "left");
        }
        return leftOp;
      });
      const historyResult = rightHistory.reduce(type.apply, structuredClone(finalResult));
      assert.deepEqual(leftHistory.reduce(type.apply, structuredClone(rightFinal)), historyResult);
      cases.push([
        family, index, snapshot, left, right, second, third,
        leftResult, rightResult, secondResult, finalResult, lr,
        leftPrime, rightPrime, type.transform(left, right, "left"),
        type.transform(right, left, "right"), type.invert(left), compose,
        rightSecond, rightFinal, historyResult,
      ]);
      snapshot = leftResult;
    }
    delete json0._testStringSubtype;
  }
  return cases;
}

function moonLiteral(name, records) {
  const lines = records.map((entry, index) => {
    const suffix = index === records.length - 1 ? "" : ",";
    return `  #|${JSON.stringify(entry)}${suffix}`;
  });
  return `///|\nlet ${name} : String =\n  #|[\n${lines.join("\n")}\n  #|]\n`;
}

const fixed = await captureTests();
const properties = propertyCases();
const file = fileURLToPath(new URL("../../upstream_data_wbtest.mbt", import.meta.url));
const content = `// Generated by test/oracle/fixtures.mjs from ot-json0@1.1.0 (seed ${seed}).\n`
  + `// Upstream test material: Copyright 2011 ottypes library contributors.\n`
  + `// Fuzzer source: Copyright 2011-2014 ottypes library contributors.\n`
  + `// License copies and provenance: THIRD_PARTY_NOTICES.md and docs/provenance.md.\n\n`
  + moonLiteral("upstream_fixed", fixed) + "\n" + moonLiteral("upstream_properties", properties);
if (process.argv.includes("--check")) {
  assert.equal(readFileSync(file, "utf8").replaceAll("\r\n", "\n"), content);
} else {
  writeFileSync(file, content);
}
console.log(`${fixed.length} fixed calls, ${properties.length} generated cases, seed ${seed}`);
