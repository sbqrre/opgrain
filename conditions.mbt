///|
#derive(@debug.Debug)
pub(all) enum Condition {
  RootPresent
  PathPresent(Path)
  PathAbsent(Path)
  EqualValue(Path, Json)
  NumberRange(Path, Double?, Double?)
  StringIncludes(Path, String)
  LengthRange(Path, Int32, Int32)
  UniqueListKey(Path, String)
  AllConditions(Array[Condition])
  AnyCondition(Array[Condition])
  Negated(Condition)
}

///|
pub extend Condition with @debug.Debug::{to_repr}

///|
#derive(@debug.Debug)
pub(all) suberror GuardError {
  InvalidCondition(String)
  GuardRejected(Bool, Int32)
  GuardApplyRejected(VerificationError)
  GuardEvaluation(OpError)
}

///|
pub extend GuardError with @debug.Debug::{to_repr}

///|
priv struct GuardBudget {
  mut remaining : Int32
}

///|
fn guard_value(snapshot : Snapshot, path : Path) -> Json? {
  if snapshot.contains_path(path) {
    Some(
      lookup_value(snapshot.value, path.segments, path.length()) catch {
        _ => abort("checked path disappeared")
      },
    )
  } else {
    None
  }
}

///|
fn test_condition(
  snapshot : Snapshot,
  condition : Condition,
  budget : GuardBudget,
  depth : Int32,
) -> Bool raise GuardError {
  guard depth < 256 && budget.remaining > 0 else {
    raise InvalidCondition("condition evaluation budget exhausted")
  }
  budget.remaining -= 1
  match condition {
    RootPresent => snapshot.value is Some(_)
    PathPresent(path) => snapshot.contains_path(path)
    PathAbsent(path) => !snapshot.contains_path(path)
    EqualValue(path, expected) => {
      let expected = copy_checked_json(expected) catch {
        error => raise GuardEvaluation(error)
      }
      match guard_value(snapshot, path) {
        Some(actual) => same_json(actual, expected)
        None => false
      }
    }
    NumberRange(path, minimum, maximum) => {
      if minimum is Some(value) {
        ignore(
          checked_number(value) catch {
            _ => raise InvalidCondition("non-finite minimum")
          },
        )
      }
      if maximum is Some(value) {
        ignore(
          checked_number(value) catch {
            _ => raise InvalidCondition("non-finite maximum")
          },
        )
      }
      if minimum is Some(low) && maximum is Some(high) && low > high {
        raise InvalidCondition("reversed numeric range")
      }
      guard guard_value(snapshot, path) is Some(Number(value, ..)) else {
        return false
      }
      (minimum is None || (minimum is Some(low) && value >= low)) &&
      (maximum is None || (maximum is Some(high) && value <= high))
    }
    StringIncludes(path, part) =>
      match guard_value(snapshot, path) {
        Some(String(text)) => text.contains(part)
        _ => false
      }
    LengthRange(path, minimum, maximum) => {
      guard minimum >= 0 && maximum >= minimum else {
        raise InvalidCondition("invalid length range")
      }
      let length = match guard_value(snapshot, path) {
        Some(String(text)) => text.length()
        Some(Array(items)) => items.length()
        Some(Object(fields)) => fields.length()
        _ => return false
      }
      length >= minimum && length <= maximum
    }
    UniqueListKey(path, key) => {
      guard guard_value(snapshot, path) is Some(Array(items)) else {
        return false
      }
      list_identity(items, key) is Some(_)
    }
    AllConditions(conditions) => {
      for condition in conditions {
        if !test_condition(snapshot, condition, budget, depth + 1) {
          return false
        }
      }
      true
    }
    AnyCondition(conditions) => {
      for condition in conditions {
        if test_condition(snapshot, condition, budget, depth + 1) {
          return true
        }
      }
      false
    }
    Negated(condition) =>
      !test_condition(snapshot, condition, budget, depth + 1)
  }
}

///|
pub fn Snapshot::test_condition(
  self : Snapshot,
  condition : Condition,
) -> Bool raise GuardError {
  test_condition(self, condition, { remaining: 100000, }, 0)
}

///|
/// Check preconditions and postconditions around an atomic verified update.
pub fn Engine::apply_when(
  self : Engine,
  snapshot : Snapshot,
  operation : Operation,
  before : Array[Condition],
  after~ : Array[Condition] = [],
) -> Snapshot raise GuardError {
  let budget = GuardBudget::{ remaining: 100000, }
  for index, condition in before {
    if !test_condition(snapshot, condition, budget, 0) {
      raise GuardRejected(false, index)
    }
  }
  let result = self.apply_snapshot_verified(snapshot, operation) catch {
    error => raise GuardApplyRejected(error)
  }
  for index, condition in after {
    if !test_condition(result, condition, budget, 0) {
      raise GuardRejected(true, index)
    }
  }
  result
}
