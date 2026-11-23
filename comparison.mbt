///|
fn same_json(left : Json, right : Json) -> Bool {
  let pending = [(left, right)]
  while pending.pop() is Some((left, right)) {
    match (left, right) {
      (Null, Null) | (True, True) | (False, False) => ()
      (Number(a, ..), Number(b, ..)) if a == b => ()
      (String(a), String(b)) if a == b => ()
      (Array(a), Array(b)) => {
        if a.length() != b.length() {
          return false
        }
        for index in 0..<a.length() {
          pending.push((a[index], b[index]))
        }
      }
      (Object(a), Object(b)) => {
        if a.length() != b.length() {
          return false
        }
        for key, value in a {
          guard b.get(key) is Some(other) else { return false }
          pending.push((value, other))
        }
      }
      _ => return false
    }
  }
  true
}

///|
fn same_snapshot(left : Snapshot, right : Snapshot) -> Bool {
  same_optional_json(left.value, right.value)
}

///|
fn same_optional_json(left : Json?, right : Json?) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(left), Some(right)) => same_json(left, right)
    _ => false
  }
}

///|
/// Compare valid owned snapshots without recursive container equality.
pub fn Snapshot::equivalent(self : Snapshot, other : Snapshot) -> Bool {
  same_snapshot(self, other)
}

///|
pub fn Operation::wire_equivalent(self : Operation, other : Operation) -> Bool {
  same_json(self.to_json(), other.to_json())
}

///|
pub(all) struct ComparisonLimits {
  max_visits : Int32
  max_differences : Int32
  max_depth : Int32
}

///|
pub fn ComparisonLimits::default() -> ComparisonLimits {
  { max_visits: 1000000, max_differences: 10000, max_depth: 1024, }
}

///|
#derive(@debug.Debug)
pub(all) suberror ComparisonError {
  InvalidComparisonLimits
  ComparisonBudget(String, Int32)
}

///|
pub extend ComparisonError with @debug.Debug::{to_repr}

///|
#derive(Eq, @debug.Debug)
pub(all) enum DifferenceKind {
  ValueChanged
  ValueAdded
  ValueRemoved
  ValueTypeChanged
}

///|
pub extend DifferenceKind with Eq::{equal, not_equal}

///|
pub extend DifferenceKind with @debug.Debug::{to_repr}

///|
pub struct ValueDifference {
  priv path : Path
  priv before : Json?
  priv after : Json?
  priv kind : DifferenceKind
}

///|
pub fn ValueDifference::path(self : ValueDifference) -> Path {
  self.path
}

///|
pub fn ValueDifference::before(self : ValueDifference) -> Json? {
  self.before.map(copy_json)
}

///|
pub fn ValueDifference::after(self : ValueDifference) -> Json? {
  self.after.map(copy_json)
}

///|
pub fn ValueDifference::kind(self : ValueDifference) -> DifferenceKind {
  self.kind
}

///|
priv struct ComparisonTask {
  path : Array[PathSegment]
  before : Json?
  after : Json?
}

///|
pub struct ValueComparison {
  priv differences : Array[ValueDifference]
  priv visits : Int32
}

///|
pub fn ValueComparison::differences(
  self : ValueComparison,
) -> Array[ValueDifference] {
  self.differences.copy()
}

///|
pub fn ValueComparison::visits(self : ValueComparison) -> Int32 {
  self.visits
}

///|
pub fn ValueComparison::equal(self : ValueComparison) -> Bool {
  self.differences.is_empty()
}

///|
fn json_type(value : Json) -> Int32 {
  match value {
    Null => 0
    True | False => 1
    Number(_) => 2
    String(_) => 3
    Array(_) => 4
    Object(_) => 5
  }
}

///|
/// Enumerate leaf differences deterministically. A resource limit raises an
/// error rather than returning an incomplete report labelled equal.
pub fn Snapshot::compare(
  self : Snapshot,
  other : Snapshot,
  limits~ : ComparisonLimits = ComparisonLimits::default(),
) -> ValueComparison raise ComparisonError {
  guard limits.max_visits >= 0 &&
    limits.max_differences >= 0 &&
    limits.max_depth >= 0 else {
    raise InvalidComparisonLimits
  }
  let pending = [
    ComparisonTask::{ path: [], before: self.value, after: other.value, },
  ]
  let differences : Array[ValueDifference] = []
  let mut visits = 0
  while pending.pop() is Some(task) {
    guard visits < limits.max_visits else {
      raise ComparisonBudget("visits", limits.max_visits)
    }
    guard task.path.length() <= limits.max_depth else {
      raise ComparisonBudget("depth", limits.max_depth)
    }
    visits += 1
    let kind = match (task.before, task.after) {
      (None, None) => continue
      (None, Some(_)) => ValueAdded
      (Some(_), None) => ValueRemoved
      (Some(Array(before)), Some(Array(after))) => {
        let length = before.length().max(after.length())
        for offset in 0..<length {
          let index = length - offset - 1
          pending.push({
            path: child_path(task.path, Index(index)),
            before: before.get(index),
            after: after.get(index),
          })
        }
        continue
      }
      (Some(Object(before)), Some(Object(after))) => {
        let keys = before.keys().to_array()
        for key, _ in after {
          if !before.contains(key) {
            keys.push(key)
          }
        }
        keys.sort()
        for offset in 0..<keys.length() {
          let key = keys[keys.length() - offset - 1]
          pending.push({
            path: child_path(task.path, Key(key)),
            before: before.get(key),
            after: after.get(key),
          })
        }
        continue
      }
      (Some(before), Some(after)) => {
        if same_json(before, after) {
          continue
        }
        if json_type(before) == json_type(after) {
          ValueChanged
        } else {
          ValueTypeChanged
        }
      }
    }
    guard differences.length() < limits.max_differences else {
      raise ComparisonBudget("differences", limits.max_differences)
    }
    differences.push({
      path: { segments: task.path, },
      before: task.before,
      after: task.after,
      kind,
    })
  }
  { differences, visits, }
}
