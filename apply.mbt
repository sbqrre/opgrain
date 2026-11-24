// JSON0/text0 semantics adapted from ottypes/json0, ot-json0@1.1.0.
// Copyright 2011 ottypes library contributors.
// MoonBit implementation and adaptations copyright (c) 2026 sbqrre.
// See THIRD_PARTY_NOTICES.md and LICENSES/ot-json0-1.1.0.txt.

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
  persistent : Bool,
  update : (Json) -> Json raise OpError,
) -> Json raise OpError {
  let parents = []
  let mut current = value
  for offset in 0..<length {
    let child = match (current, path[offset]) {
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
    parents.push(if persistent { shallow_copy(current) } else { current })
    current = child
  }
  let mut result = update(
    if persistent {
      shallow_copy(current)
    } else {
      current
    },
  )
  for offset = length - 1; offset >= 0; offset = offset - 1 {
    let parent = parents[offset]
    match (parent, path[offset]) {
      (Array(items), Index(index)) => items[index] = result
      (Object(fields), Key(key)) => fields[key] = result
      _ => abort("validated parent changed during update")
    }
    result = parent
  }
  result
}

///|
fn Engine::apply_component(
  self : Engine,
  snapshot : Json?,
  component : Component,
  persistent~ : Bool = false,
) -> Json? raise OpError {
  let { path, action, } = component
  if path.is_empty() && action is ObjectEdit(insert, _) {
    return insert.map(copy_json)
  }
  guard snapshot is Some(snapshot) else { raise MissingRoot }
  let length = path.length()
  let output = match action {
    Add(amount) =>
      update_at(snapshot, path, length, persistent, value => {
        guard value is Number(n, ..) else {
          raise InvalidPath(path.copy(), "number addition requires a number")
        }
        Json::number(checked_number(n + amount))
      })
    ListEdit(insert, delete) =>
      update_at(snapshot, path, length - 1, persistent, parent => {
        let items = require_list(parent, path)
        guard path[length - 1] is Index(index) else {
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
      update_at(snapshot, path, length - 1, persistent, parent => {
        let items = require_list(parent, path)
        guard path[length - 1] is Index(source) else {
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
      update_at(snapshot, path, length - 1, persistent, parent => {
        let fields = require_object(parent, path)
        guard path[length - 1] is Key(key) else {
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
      update_at(snapshot, path, length - 1, persistent, value => {
        guard path[length - 1] is Index(position) else {
          raise InvalidPath(path.copy(), "legacy text edit requires a string")
        }
        let edit = TextEdit::{ position, insert, text, }
        match self.subtypes.get("text0") {
          Some(subtype) =>
            copy_checked_json(
              (subtype.apply)(copy_json(value), encode_text0([edit])),
            )
          None => {
            guard value is String(value) else {
              raise InvalidPath(
                path.copy(),
                "legacy text edit requires a string",
              )
            }
            Json::string(edit_string(value, edit, path))
          }
        }
      })
    SubtypeEdit(kind, payload) =>
      update_at(snapshot, path, length, persistent, value => {
        match self.subtypes.get(kind) {
          Some(subtype) =>
            copy_checked_json(
              (subtype.apply)(copy_json(value), copy_json(payload)),
            )
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
pub fn Engine::check_valid_op(
  self : Engine,
  value : Json,
) -> Unit raise OpError {
  let op = Operation::from_json(value)
  for c in op.components {
    self.ensure_registered(c)
  }
}

///|
/// Apply an operation to a detached copy. None represents a missing root.
pub fn Engine::apply_optional(
  self : Engine,
  snapshot : Json?,
  op : Operation,
) -> Json? raise OpError {
  let mut result = snapshot.map(copy_checked_json)
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
  let mut result = snapshot.map(copy_checked_json)
  for component in op.components {
    result = self.apply_component(result, component)
    on_step({ components: [component], }, result.map(copy_json))
  }
  result
}
