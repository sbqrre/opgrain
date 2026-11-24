// JSON0/text0 semantics adapted from ottypes/json0, ot-json0@1.1.0.
// Copyright 2011 ottypes library contributors.
// MoonBit implementation and adaptations copyright (c) 2026 sbqrre.
// See THIRD_PARTY_NOTICES.md and LICENSES/ot-json0-1.1.0.txt.

///|
pub fn path_matches(
  left : Array[PathSegment],
  right : Array[PathSegment],
  ignore_last~ : Bool = false,
) -> Bool {
  guard left.length() == right.length() else { return false }
  for
    i in 0..<(left.length() -
    (if ignore_last && !left.is_empty() { 1 } else { 0 })) {
    if left[i] != right[i] {
      return false
    }
  }
  true
}

///|
fn legacy_parts(component : Component) -> (Array[PathSegment], TextEdit)? {
  guard component.action is LegacyText(insert, text) &&
    component.path.last() is Some(Index(position)) else {
    return None
  }
  let parent = component.path.copy()
  ignore(parent.pop())
  Some((parent, { insert, text, position, }))
}

///|
fn legacy_component(path : Array[PathSegment], edit : TextEdit) -> Component {
  let path = path.copy()
  path.push(Index(edit.position))
  { path, action: LegacyText(edit.insert, edit.text), }
}

///|
fn strict_primitive_equal(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Number(x, ..), Number(y, ..)) => x == y
    (String(x), String(y)) => x == y
    (Null, Null) | (True, True) | (False, False) => true
    _ => false
  }
}

///|
fn Engine::ensure_registered(
  self : Engine,
  c : Component,
) -> Unit raise OpError {
  if c.action is SubtypeEdit(kind, payload) {
    if self.subtypes.get(kind) is None {
      guard kind == "text0" else { raise UnknownSubtype(kind) }
      ignore(decode_text0(payload))
    }
  }
}

///|
fn Engine::compose_subtype(
  self : Engine,
  kind : String,
  a : Json,
  b : Json,
) -> Json raise OpError {
  match self.subtypes.get(kind) {
    Some(subtype) =>
      copy_checked_json((subtype.compose)(copy_json(a), copy_json(b)))
    None if kind == "text0" =>
      encode_text0(compose_text0(decode_text0(a), decode_text0(b)))
    None => raise UnknownSubtype(kind)
  }
}

///|
fn Engine::append_component(
  self : Engine,
  dest : Array[Component],
  c : Component,
) -> Unit raise OpError {
  guard dest.last() is Some(last) else {
    dest.push(c)
    return
  }
  let end = dest.length() - 1
  if legacy_parts(last) is Some((parent, first)) &&
    legacy_parts(c) is Some((other_parent, second)) {
    if path_matches(parent, other_parent) {
      let edits = self.compose_subtype(
        "text0",
        encode_text0([first]),
        encode_text0([second]),
      )
      ignore(dest.pop())
      for edit in decode_text0(edits) {
        dest.push(legacy_component(parent, edit))
      }
    } else {
      dest.push(c)
    }
    return
  }
  guard path_matches(last.path, c.path) else {
    dest.push(c)
    return
  }
  let merged = match (last.action, c.action) {
    (SubtypeEdit(kind, a), SubtypeEdit(other_kind, b)) if kind == other_kind =>
      SubtypeEdit(kind, self.compose_subtype(kind, a, b))
    (Add(a), Add(b)) => Add(checked_number(a + b))
    (ListEdit(Some(inserted), original), ListEdit(None, Some(deleted))) if strict_primitive_equal(
        inserted, deleted,
      ) =>
      match original {
        Some(_) => ListEdit(None, original)
        None => {
          ignore(dest.pop())
          return
        }
      }
    (ObjectEdit(None, Some(old)), ObjectEdit(Some(next), None)) =>
      ObjectEdit(Some(next), Some(old))
    (ObjectEdit(Some(_), original), ObjectEdit(next, Some(_))) => {
      if next is None && original is None {
        ignore(dest.pop())
        return
      }
      ObjectEdit(next, original)
    }
    (_, Move(to)) if c.path.last() == Some(Index(to)) => return
    _ => {
      dest.push(c)
      return
    }
  }
  dest[end] = { path: last.path, action: merged, }
}

///|
pub fn Engine::compose(
  self : Engine,
  first : Operation,
  second : Operation,
) -> Operation raise OpError {
  let components = first.components.copy()
  for c in first.components {
    self.ensure_registered(c)
  }
  for c in second.components {
    self.ensure_registered(c)
    self.append_component(components, c)
  }
  { components, }
}

///|
pub fn compose(
  first : Operation,
  second : Operation,
) -> Operation raise OpError {
  Engine::new().compose(first, second)
}

///|
pub fn Engine::append(
  self : Engine,
  dest : Operation,
  component : Component,
) -> Operation raise OpError {
  self.compose(dest, { components: [component], })
}

///|
pub fn Engine::normalize(
  self : Engine,
  value : Json,
) -> Operation raise OpError {
  let values = match value {
    Array(items) => items
    _ => [value]
  }
  let components = []
  for i, value in values {
    let component = decode_component(value, i, default_path=true)
    self.ensure_registered(component)
    self.append_component(components, component)
  }
  { components, }
}

///|
pub fn normalize(value : Json) -> Operation raise OpError {
  Engine::new().normalize(value)
}
