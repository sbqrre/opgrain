///|
#derive(@debug.Debug)
pub(all) suberror VerificationError {
  InvalidSnapshot(OpError)
  ComponentFailed(Int32, Array[PathSegment], OpError)
  StalePreimage(Int32, Array[PathSegment], Json?, Json?)
}

///|
pub extend VerificationError with @debug.Debug::{to_repr}

///|
fn lookup_value(
  snapshot : Json?,
  path : Array[PathSegment],
  length : Int32,
) -> Json raise OpError {
  guard snapshot is Some(root) else { raise MissingRoot }
  let mut value = root
  for offset in 0..<length {
    value = match (value, path[offset]) {
      (Array(items), Index(index)) => {
        guard index >= 0 && index < items.length() else {
          raise InvalidPath(path.copy(), "list index out of bounds")
        }
        items[index]
      }
      (Object(fields), Key(key)) => {
        guard fields.get(key) is Some(child) else {
          raise InvalidPath(path.copy(), "object key does not exist")
        }
        child
      }
      _ =>
        raise InvalidPath(path.copy(), "path segment does not match container")
    }
  }
  value
}

///|
fn object_preimage(
  snapshot : Json?,
  path : Array[PathSegment],
) -> Json? raise OpError {
  if path.is_empty() {
    return snapshot
  }
  guard path.last() is Some(Key(key)) else {
    raise InvalidPath(path.copy(), "object edit requires a key")
  }
  let parent = lookup_value(snapshot, path, path.length() - 1)
  require_object(parent, path).get(key)
}

///|
fn list_position(
  snapshot : Json?,
  path : Array[PathSegment],
  allow_end : Bool,
) -> (Array[Json], Int32) raise OpError {
  guard path.last() is Some(Index(index)) else {
    raise InvalidPath(path.copy(), "list edit requires an index")
  }
  let parent = lookup_value(snapshot, path, path.length() - 1)
  let items = require_list(parent, path)
  guard index >= 0 &&
    index <= items.length() &&
    (allow_end || index < items.length()) else {
    raise InvalidPath(path.copy(), "list edit index out of bounds")
  }
  (items, index)
}

///|
fn list_preimage(
  snapshot : Json?,
  path : Array[PathSegment],
) -> Json raise OpError {
  let (items, index) = list_position(snapshot, path, false)
  items[index]
}

///|
fn preimage_pair(
  snapshot : Json?,
  component : Component,
) -> (Json?, Json?)? raise OpError {
  let { path, action, } = component
  match action {
    ObjectEdit(_, expected) => Some((expected, object_preimage(snapshot, path)))
    ListEdit(_, Some(expected)) =>
      Some((Some(expected), Some(list_preimage(snapshot, path))))
    _ => None
  }
}

///|
fn Engine::verify_component(
  self : Engine,
  snapshot : Json?,
  component : Component,
  index : Int32,
  persistent~ : Bool = false,
) -> Json? raise VerificationError {
  let path = component.path
  let pair = preimage_pair(snapshot, component) catch {
    error => raise ComponentFailed(index, path.copy(), error)
  }
  if pair is Some((expected, actual)) && expected != actual {
    raise StalePreimage(
      index,
      path.copy(),
      expected.map(copy_json),
      actual.map(copy_json),
    )
  }
  self.apply_component(snapshot, component, persistent~) catch {
    error => raise ComponentFailed(index, path.copy(), error)
  }
}

///|
/// Apply against a private copy and verify the preimages of object and list edits.
/// The error index refers to the operation array supplied by the caller.
pub fn Engine::apply_verified(
  self : Engine,
  snapshot : Json?,
  operation : Operation,
) -> Json? raise VerificationError {
  let mut updated = snapshot.map(copy_checked_json) catch {
    error => raise InvalidSnapshot(error)
  }
  for index, component in operation.components {
    updated = self.verify_component(updated, component, index)
  }
  updated
}
