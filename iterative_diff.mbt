///|
pub(all) struct IterativeDiffOptions {
  text : TextDiffOptions
  text_encoding : TextEncoding
  prefer_number_add : Bool
  max_visits : Int32
  max_components : Int32
  max_depth : Int32
}

///|
pub fn IterativeDiffOptions::default() -> IterativeDiffOptions {
  {
    text: TextDiffOptions::default(),
    text_encoding: Text0,
    prefer_number_add: false,
    max_visits: 1000000,
    max_components: 100000,
    max_depth: 1024,
  }
}

///|
#derive(@debug.Debug)
pub(all) suberror IterativeDiffError {
  InvalidIterativeDiffOptions
  IterativeDiffBudget(String, Int32)
  IterativeTextDiff(TextDiffError)
  IterativeDiffComponent(OpError)
  IterativeDiffVerification(VerificationError)
  IterativeDiffMismatch
}

///|
pub extend IterativeDiffError with @debug.Debug::{to_repr}

///|
pub(all) struct IterativeDiffMetrics {
  visits : Int32
  objects : Int32
  arrays : Int32
  strings : Int32
  replacements : Int32
  text_cells : Int64
}

///|
pub struct SnapshotDiff {
  priv operation : Operation
  priv before : Snapshot
  priv after : Snapshot
  priv metrics : IterativeDiffMetrics
}

///|
pub fn SnapshotDiff::operation(self : SnapshotDiff) -> Operation {
  self.operation
}

///|
pub fn SnapshotDiff::before(self : SnapshotDiff) -> Snapshot {
  self.before
}

///|
pub fn SnapshotDiff::after(self : SnapshotDiff) -> Snapshot {
  self.after
}

///|
pub fn SnapshotDiff::metrics(self : SnapshotDiff) -> IterativeDiffMetrics {
  self.metrics
}

///|
priv enum SnapshotDiffTask {
  CompareValues(Array[PathSegment], Json?, Json?)
  EmitComponent(Component)
}

///|
fn replacement_component(
  path : Array[PathSegment],
  before : Json?,
  after : Json?,
) -> Component {
  let action = match path.last() {
    Some(Index(_)) => ListEdit(after, before)
    _ => ObjectEdit(after, before)
  }
  { path, action, }
}

///|
fn push_object_diff(
  pending : Array[SnapshotDiffTask],
  path : Array[PathSegment],
  before : Map[String, Json],
  after : Map[String, Json],
) -> Unit {
  let keys = before.keys().to_array()
  for key, _ in after {
    if !before.contains(key) {
      keys.push(key)
    }
  }
  keys.sort()
  for offset in 0..<keys.length() {
    let key = keys[keys.length() - offset - 1]
    pending.push(
      CompareValues(child_path(path, Key(key)), before.get(key), after.get(key)),
    )
  }
}

///|
/// Pair the unmatched middle by position, keeping identical ends intact.
/// This avoids a quadratic list-alignment matrix. Use diff_keyed_list for IDs.
fn push_array_diff(
  pending : Array[SnapshotDiffTask],
  path : Array[PathSegment],
  before : Array[Json],
  after : Array[Json],
) -> Unit {
  let shortest = before.length().min(after.length())
  let mut prefix = 0
  while prefix < shortest && same_json(before[prefix], after[prefix]) {
    prefix += 1
  }
  let mut suffix = 0
  while suffix < shortest - prefix &&
        same_json(
          before[before.length() - suffix - 1],
          after[after.length() - suffix - 1],
        ) {
    suffix += 1
  }
  let old_end = before.length() - suffix
  let new_end = after.length() - suffix
  let paired = (old_end - prefix).min(new_end - prefix)
  let forward = []
  for index in (prefix + paired)..<old_end {
    // Delete repeatedly at the first unpaired position in the evolving list.
    forward.push(
      EmitComponent({
        path: child_path(path, Index(prefix + paired)),
        action: ListEdit(None, Some(before[index])),
      }),
    )
  }
  for index in (prefix + paired)..<new_end {
    forward.push(
      EmitComponent({
        path: child_path(path, Index(index)),
        action: ListEdit(Some(after[index]), None),
      }),
    )
  }
  for offset in 0..<paired {
    let index = prefix + offset
    forward.push(
      CompareValues(
        child_path(path, Index(index)),
        Some(before[index]),
        Some(after[index]),
      ),
    )
  }
  forward.rev_in_place()
  pending.append(forward)
}

///|
/// Generate edits with an explicit work stack and a shared text-alignment budget.
/// Inputs are opaque validated snapshots, and every generated preimage is verified.
pub fn Engine::diff_snapshots(
  self : Engine,
  before : Snapshot,
  after : Snapshot,
  options~ : IterativeDiffOptions = IterativeDiffOptions::default(),
) -> SnapshotDiff raise IterativeDiffError {
  guard options.max_visits >= 0 &&
    options.max_components >= 0 &&
    options.max_depth >= 0 &&
    options.text.max_cells >= 0L &&
    options.text.max_units >= 0 else {
    raise InvalidIterativeDiffOptions
  }
  let pending = [CompareValues([], before.value, after.value)]
  let components = []
  let mut visits = 0
  let mut objects = 0
  let mut arrays = 0
  let mut strings = 0
  let mut replacements = 0
  let mut text_cells = 0L
  while pending.pop() is Some(task) {
    match task {
      EmitComponent(component) => {
        guard components.length() < options.max_components else {
          raise IterativeDiffBudget("components", options.max_components)
        }
        components.push(component)
      }
      CompareValues(path, previous, next) => {
        guard visits < options.max_visits else {
          raise IterativeDiffBudget("visits", options.max_visits)
        }
        guard path.length() <= options.max_depth else {
          raise IterativeDiffBudget("depth", options.max_depth)
        }
        visits += 1
        match (previous, next) {
          (None, None) => ()
          (Some(Object(old)), Some(Object(target))) => {
            objects += 1
            push_object_diff(pending, path, old, target)
          }
          (Some(Array(old)), Some(Array(target))) => {
            arrays += 1
            push_array_diff(pending, path, old, target)
          }
          (Some(String(old)), Some(String(target))) if !self.subtypes.contains(
              "text0",
            ) => {
            strings += 1
            if old == target {
              continue
            }
            let difference = diff_text(old, target, options={
              ..options.text,
              max_cells: options.text.max_cells - text_cells,
            }) catch {
              error => raise IterativeTextDiff(error)
            }
            text_cells += difference.metrics.compared_cells
            let edits = text_components(
              path,
              difference.operation.edits,
              options.text_encoding,
            )
            for offset in 0..<edits.length() {
              pending.push(EmitComponent(edits[edits.length() - offset - 1]))
            }
          }
          (Some(Number(old, ..)), Some(Number(target, ..))) if options.prefer_number_add &&
            old != target &&
            exact_delta(old, target) is Some(delta) =>
            pending.push(EmitComponent({ path, action: Add(delta), }))
          (Some(old), Some(target)) if same_json(old, target) => ()
          _ => {
            replacements += 1
            pending.push(
              EmitComponent(replacement_component(path, previous, next)),
            )
          }
        }
      }
    }
  }
  let operation = Operation::{ components, }
  let actual = self.apply_snapshot_verified(before, operation) catch {
    error => raise IterativeDiffVerification(error)
  }
  guard actual.equivalent(after) else { raise IterativeDiffMismatch }
  {
    operation,
    before,
    after: actual,
    metrics: { visits, objects, arrays, strings, replacements, text_cells, },
  }
}
