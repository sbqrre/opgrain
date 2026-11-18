///|
/// An operation subtype handles its own JSON payload and snapshot.
pub(all) struct Subtype {
  apply : (Json, Json) -> Json raise OpError
  compose : (Json, Json) -> Json raise OpError
  invert : (Json) -> Json raise OpError
  transform : (Json, Json, Side) -> Json raise OpError
}

///|
/// Each engine owns its subtype registry.
pub struct Engine {
  priv subtypes : Map[String, Subtype]
}

///|
pub fn Engine::new() -> Engine {
  { subtypes: Map([]), }
}

///|
pub fn Engine::register_subtype(
  self : Engine,
  name : String,
  subtype : Subtype,
) -> Unit {
  self.subtypes[name] = subtype
}

///|
fn update_at(
  value : Json,
  path : Array[PathSegment],
  length : Int32,
  offset : Int32,
  update : (Json) -> Json raise OpError,
) -> Json raise OpError {
  if offset == length {
    return update(value)
  }
  match (value, path[offset]) {
    (Array(items), Index(index)) => {
      guard index < items.length() else {
        raise InvalidPath(path.copy(), "list index out of bounds")
      }
      items[index] = update_at(items[index], path, length, offset + 1, update)
    }
    (Object(fields), Key(key)) => {
      guard fields.get(key) is Some(child) else {
        raise InvalidPath(path.copy(), "object key does not exist")
      }
      fields[key] = update_at(child, path, length, offset + 1, update)
    }
    _ => raise InvalidPath(path.copy(), "path segment does not match container")
  }
  value
}

///|
fn Engine::apply_component(
  self : Engine,
  snapshot : Json?,
  component : Component,
) -> Json? raise OpError {
  let { path, action, } = component
  if path.is_empty() && action is ObjectEdit(insert, _) {
    return insert.map(copy_json)
  }
  guard snapshot is Some(snapshot) else { raise MissingRoot }
  let length = path.length()
  let output = match action {
    Add(amount) =>
      update_at(snapshot, path, length, 0, value => {
        guard value is Number(n, ..) else {
          raise InvalidPath(path.copy(), "number addition requires a number")
        }
        Json::number(checked_number(n + amount))
      })
    ListEdit(insert, delete) =>
      update_at(snapshot, path, length - 1, 0, parent => {
        guard parent is Array(items) && path[length - 1] is Index(index) else {
          raise InvalidPath(path.copy(), "list edit requires a list")
        }
        guard index <= items.length() &&
          (delete is None || index < items.length()) else {
          raise InvalidPath(path.copy(), "list edit index out of bounds")
        }
        match (insert, delete) {
          (Some(item), Some(_)) => items[index] = copy_json(item)
          (Some(item), None) => items.insert(index, copy_json(item))
          (None, Some(_)) => ignore(items.remove(index))
          (None, None) => ()
        }
        parent
      })
    Move(destination) =>
      update_at(snapshot, path, length - 1, 0, parent => {
        guard parent is Array(items) && path[length - 1] is Index(source) else {
          raise InvalidPath(path.copy(), "list move requires a list")
        }
        guard source < items.length() && destination < items.length() else {
          raise InvalidPath(path.copy(), "list move index out of bounds")
        }
        if source != destination {
          let item = items.remove(source)
          items.insert(destination, item)
        }
        parent
      })
    ObjectEdit(insert, _) =>
      update_at(snapshot, path, length - 1, 0, parent => {
        guard parent is Object(fields) && path[length - 1] is Key(key) else {
          raise InvalidPath(path.copy(), "object edit requires an object")
        }
        match insert {
          Some(item) => fields[key] = copy_json(item)
          None => {
            guard fields.get(key) is Some(_) else {
              raise InvalidPath(path.copy(), "object key does not exist")
            }
            fields.remove(key)
          }
        }
        parent
      })
    LegacyText(insert, text) =>
      update_at(snapshot, path, length - 1, 0, value => {
        guard value is String(value) && path[length - 1] is Index(position) else {
          raise InvalidPath(path.copy(), "legacy text edit requires a string")
        }
        Json::string(edit_string(value, { position, insert, text, }, path))
      })
    SubtypeEdit(kind, payload) =>
      update_at(snapshot, path, length, 0, value => {
        match self.subtypes.get(kind) {
          Some(subtype) =>
            copy_json((subtype.apply)(copy_json(value), copy_json(payload)))
          None if kind == "text0" => {
            guard value is String(text) else {
              raise InvalidPath(path.copy(), "text0 requires a string")
            }
            let mut result = text
            for edit in decode_text0(payload) {
              result = edit_string(result, edit, path)
            }
            Json::string(result)
          }
          None => raise UnknownSubtype(kind)
        }
      })
  }
  Some(output)
}

///|
/// Apply an operation to a detached copy. None represents a missing root.
pub fn Engine::apply_optional(
  self : Engine,
  snapshot : Json?,
  op : Operation,
) -> Json? raise OpError {
  let mut result = snapshot.map(copy_json)
  for component in op.components {
    result = self.apply_component(result, component)
  }
  result
}

///|
pub fn Engine::apply(
  self : Engine,
  snapshot : Json,
  op : Operation,
) -> Json raise OpError {
  guard self.apply_optional(Some(snapshot), op) is Some(result) else {
    raise MissingRoot
  }
  result
}

///|
pub fn apply(snapshot : Json, op : Operation) -> Json raise OpError {
  Engine::new().apply(snapshot, op)
}

///|
pub fn Engine::incremental_apply(
  self : Engine,
  snapshot : Json?,
  op : Operation,
  on_step : (Operation, Json?) -> Unit,
) -> Json? raise OpError {
  let mut result = snapshot.map(copy_json)
  for component in op.components {
    result = self.apply_component(result, component)
    on_step({ components: [component], }, result.map(copy_json))
  }
  result
}
