///|
pub(all) struct DiffOptions {
  text_encoding : TextEncoding
  alignment_cells : Int32
  list_identity_key : String?
  prefer_number_add : Bool
}

///|
pub fn DiffOptions::default() -> DiffOptions {
  {
    text_encoding: Text0,
    alignment_cells: 16_384,
    list_identity_key: None,
    prefer_number_add: false,
  }
}

///|
priv struct Diff {
  draft : Draft
  options : DiffOptions
  budget : AlignmentBudget
}

///|
/// Generate a sequential JSON0 operation with correct preimages.
pub fn Engine::diff(
  self : Engine,
  before : Json?,
  after : Json?,
  options~ : DiffOptions = DiffOptions::default(),
) -> Operation raise OpError {
  let draft = self.draft(before)
  let state = Diff::{
    draft,
    options,
    budget: { cells: options.alignment_cells, },
  }
  let target = after.map(copy_checked_json)
  match (draft.snapshot(), target) {
    (Some(previous), Some(next)) => state.reconcile([], previous, next)
    (None, Some(next)) => draft.set([], next)
    (Some(_), None) => draft.remove([])
    (None, None) => ()
  }
  draft.operation()
}

///|
fn Diff::replace(
  self : Diff,
  path : Array[PathSegment],
  value : Json,
) -> Unit raise OpError {
  if path.last() is Some(Index(_)) {
    self.draft.replace_item(path, value)
  } else {
    self.draft.set(path, value)
  }
}

///|
fn exact_delta(before : Double, after : Double) -> Double? {
  let delta = after - before
  if !delta.is_nan() &&
    !delta.is_inf() &&
    before + delta == after &&
    after - delta == before {
    Some(delta)
  } else {
    None
  }
}

///|
fn Diff::reconcile(
  self : Diff,
  path : Array[PathSegment],
  before : Json,
  after : Json,
) -> Unit raise OpError {
  if before == after {
    return
  }
  match (before, after) {
    (Object(previous), Object(next)) => self.object(path, previous, next)
    (Array(previous), Array(next)) => self.list(path, previous, next)
    (String(previous), String(next)) if self.draft.engine.subtypes.get("text0")
      is None => self.string(path, previous, next)
    (Number(previous, ..), Number(next, ..)) if self.options.prefer_number_add &&
      exact_delta(previous, next) is Some(delta) =>
      self.draft.add_number(path, delta)
    _ => self.replace(path, after)
  }
}

///|
fn Diff::object(
  self : Diff,
  path : Array[PathSegment],
  before : Map[String, Json],
  after : Map[String, Json],
) -> Unit raise OpError {
  let keys = []
  for key, _ in before {
    keys.push(key)
  }
  for key, _ in after {
    if !before.contains(key) {
      keys.push(key)
    }
  }
  keys.sort()
  for key in keys {
    let child = child_path(path, Key(key))
    match (before.get(key), after.get(key)) {
      (Some(previous), Some(next)) => self.reconcile(child, previous, next)
      (Some(_), None) => self.draft.remove(child)
      (None, Some(next)) => self.draft.set(child, next)
      (None, None) => ()
    }
  }
}

///|
fn Diff::string(
  self : Diff,
  path : Array[PathSegment],
  before : String,
  after : String,
) -> Unit raise OpError {
  let matches = alignment(
    before.length(),
    after.length(),
    (i, j) => before.code_unit_at(i) == after.code_unit_at(j),
    self.budget,
  )
  let edits = []
  for i in 1..<matches.length() {
    let previous = matches[i - 1]
    let next = matches[i]
    let remove_start = previous.before + 1
    let position = previous.after + 1
    if remove_start < next.before {
      edits.push({
        position,
        insert: false,
        text: code_slice(before, remove_start, next.before),
      })
    }
    if position < next.after {
      edits.push({
        position,
        insert: true,
        text: code_slice(after, position, next.after),
      })
    }
  }
  for component in text_components(path, edits, self.options.text_encoding) {
    self.draft.record(component)
  }
}

///|
priv struct ListIdentity {
  order : Array[String]
  items : Map[String, Json]
}

///|
fn list_identity(items : Array[Json], key : String) -> ListIdentity? {
  let index = ListIdentity::{ order: [], items: Map([]), }
  for value in items {
    guard value is Object(object) &&
      object.get(key) is Some(String(id)) &&
      !index.items.contains(id) else {
      return None
    }
    index.order.push(id)
    index.items[id] = value
  }
  Some(index)
}

///|
fn Diff::list_by_identity(
  self : Diff,
  path : Array[PathSegment],
  before : ListIdentity,
  after : ListIdentity,
) -> Unit raise OpError {
  let current = before.order.copy()
  for i = current.length() - 1; i >= 0; i = i - 1 {
    if !after.items.contains(current[i]) {
      self.draft.remove_item(child_path(path, Index(i)))
      ignore(current.remove(i))
    }
  }
  for target, id in after.order {
    let child = child_path(path, Index(target))
    let next = after.items[id]
    guard before.items.get(id) is Some(previous) else {
      self.draft.insert_item(child, next)
      current.insert(target, id)
      continue
    }
    let mut source = target
    while source < current.length() && current[source] != id {
      source += 1
    }
    if source != target {
      self.draft.move_item(child_path(path, Index(source)), target)
      ignore(current.remove(source))
      current.insert(target, id)
    }
    self.reconcile(child, previous, next)
  }
}

///|
fn Diff::list_gap(
  self : Diff,
  path : Array[PathSegment],
  before : Array[Json],
  after : Array[Json],
  previous : Anchor,
  next : Anchor,
) -> Unit raise OpError {
  let before_start = previous.before + 1
  let after_start = previous.after + 1
  let remove_count = next.before - before_start
  let insert_count = next.after - after_start
  let common = Int32::min(remove_count, insert_count)
  for i in 0..<common {
    let location = after_start + i
    self.reconcile(
      child_path(path, Index(location)),
      before[before_start + i],
      after[location],
    )
  }
  for _ in common..<remove_count {
    self.draft.remove_item(child_path(path, Index(after_start + common)))
  }
  for i in common..<insert_count {
    let location = after_start + i
    self.draft.insert_item(child_path(path, Index(location)), after[location])
  }
}

///|
fn Diff::list(
  self : Diff,
  path : Array[PathSegment],
  before : Array[Json],
  after : Array[Json],
) -> Unit raise OpError {
  if self.options.list_identity_key is Some(key) &&
    list_identity(before, key) is Some(previous) &&
    list_identity(after, key) is Some(next) {
    self.list_by_identity(path, previous, next)
    return
  }
  let matches = alignment(
    before.length(),
    after.length(),
    (i, j) => before[i] == after[j],
    self.budget,
  )
  for i in 1..<matches.length() {
    self.list_gap(path, before, after, matches[i - 1], matches[i])
  }
}
