///|
#derive(Eq, @debug.Debug)
pub(all) enum PathPattern {
  ExactKey(String)
  ExactIndex(Int32)
  AnyKey
  AnyIndex
  Descendants
}

///|
pub extend PathPattern with Eq::{equal, not_equal}

///|
pub extend PathPattern with @debug.Debug::{to_repr}

///|
pub(all) struct QueryLimits {
  max_visits : Int32
  max_matches : Int32
  max_depth : Int32
}

///|
pub fn QueryLimits::default() -> QueryLimits {
  { max_visits: 100000, max_matches: 10000, max_depth: 1024, }
}

///|
#derive(@debug.Debug)
pub(all) suberror QueryError {
  InvalidQuery(String)
  QueryBudget(String, Int32)
}

///|
pub extend QueryError with @debug.Debug::{to_repr}

///|
pub struct Selection {
  priv paths : Array[Path]
  priv snapshot : Snapshot
  priv visits : Int32
}

///|
pub fn Selection::paths(self : Selection) -> Array[Path] {
  self.paths.copy()
}

///|
pub fn Selection::length(self : Selection) -> Int32 {
  self.paths.length()
}

///|
pub fn Selection::visits(self : Selection) -> Int32 {
  self.visits
}

///|
pub fn Selection::values(self : Selection) -> Array[Json] raise OpError {
  self.paths.map(path => self.snapshot.at(path))
}

///|
pub fn Selection::snapshots(self : Selection) -> Array[Snapshot] raise OpError {
  self.paths.map(path => self.snapshot.subtree(path.segments))
}

///|
fn pattern_step(pattern : PathPattern, segment : PathSegment) -> Bool {
  match (pattern, segment) {
    (ExactKey(a), Key(b)) => a == b
    (ExactIndex(a), Index(b)) => a == b
    (AnyKey, Key(_)) | (AnyIndex, Index(_)) => true
    _ => false
  }
}

///|
fn pattern_closure(
  patterns : Array[PathPattern],
  states : Array[Int32],
) -> Array[Int32] {
  let active = Array::make(patterns.length() + 1, false)
  for state in states {
    active[state] = true
  }
  for i in 0..<patterns.length() {
    if active[i] && patterns[i] == Descendants {
      active[i + 1] = true
    }
  }
  let result = []
  for index, present in active {
    if present {
      result.push(index)
    }
  }
  result
}

///|
fn pattern_advance(
  patterns : Array[PathPattern],
  states : Array[Int32],
  segment : PathSegment,
) -> Array[Int32] {
  let next = []
  for state in states {
    if state == patterns.length() {
      continue
    }
    if patterns[state] == Descendants {
      next.push(state)
    } else if pattern_step(patterns[state], segment) {
      next.push(state + 1)
    }
  }
  pattern_closure(patterns, next)
}

///|
priv struct QueryNode {
  path : Array[PathSegment]
  value : Json
  states : Array[Int32]
}

///|
/// Deterministic depth-first matching over a validated snapshot.
pub fn Snapshot::select(
  self : Snapshot,
  patterns : Array[PathPattern],
  limits~ : QueryLimits = QueryLimits::default(),
) -> Selection raise QueryError {
  guard limits.max_visits >= 0 &&
    limits.max_matches >= 0 &&
    limits.max_depth >= 0 else {
    raise InvalidQuery("negative query budget")
  }
  for pattern in patterns {
    if pattern is ExactIndex(index) && index < 0 {
      raise InvalidQuery("negative pattern index")
    }
  }
  let paths = []
  let pending = []
  if self.value is Some(value) {
    pending.push(QueryNode::{
      path: [],
      value,
      states: pattern_closure(patterns, [0]),
    })
  }
  let mut visits = 0
  while pending.pop() is Some(node) {
    guard visits < limits.max_visits else {
      raise QueryBudget("visits", visits)
    }
    visits += 1
    guard node.path.length() <= limits.max_depth else {
      raise QueryBudget("depth", node.path.length())
    }
    if node.states.contains(patterns.length()) {
      guard paths.length() < limits.max_matches else {
        raise QueryBudget("matches", paths.length())
      }
      paths.push(Path::{ segments: node.path, })
    }
    if node.states.is_empty() {
      continue
    }
    match node.value {
      Array(items) =>
        for index = items.length() - 1; index >= 0; index = index - 1 {
          let states = pattern_advance(patterns, node.states, Index(index))
          if !states.is_empty() {
            pending.push({
              path: child_path(node.path, Index(index)),
              value: items[index],
              states,
            })
          }
        }
      Object(fields) => {
        let keys = []
        for key, _ in fields {
          keys.push(key)
        }
        keys.sort()
        for index = keys.length() - 1; index >= 0; index = index - 1 {
          let key = keys[index]
          let states = pattern_advance(patterns, node.states, Key(key))
          if !states.is_empty() {
            pending.push({
              path: child_path(node.path, Key(key)),
              value: fields[key],
              states,
            })
          }
        }
      }
      _ => ()
    }
  }
  { paths, snapshot: self, visits, }
}

///|
pub fn Path::matches(self : Path, patterns : Array[PathPattern]) -> Bool {
  let mut states = pattern_closure(patterns, [0])
  for segment in self.segments {
    states = pattern_advance(patterns, states, segment)
  }
  states.contains(patterns.length())
}
