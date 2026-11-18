import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import upstream from "ot-json0";

export const json0 = upstream.type;

export function evaluate({ command, snapshot, op, other, side }) {
  switch (command) {
    case "apply":
      return json0.apply(structuredClone(snapshot), structuredClone(op));
    case "compose":
      return json0.compose(structuredClone(op), structuredClone(other));
    case "invert":
      return json0.invert(structuredClone(op));
    case "normalize":
      return json0.normalize(structuredClone(op));
    case "transform":
      return json0.transform(structuredClone(op), structuredClone(other), side);
    case "transformX":
      return json0.transformX(structuredClone(op), structuredClone(other));
    default:
      throw new Error(`Unknown oracle command: ${command}`);
  }
}

export function wireResult(value) {
  return value === undefined
    ? { present: false }
    : { present: true, value: JSON.parse(JSON.stringify(value)) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const requests = JSON.parse(readFileSync(0, "utf8"));
  const results = requests.map((request) => wireResult(evaluate(request)));
  process.stdout.write(JSON.stringify(results) + "\n");
}
