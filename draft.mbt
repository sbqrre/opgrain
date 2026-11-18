///|
/// A detached working snapshot and the sequential JSON0 operation that produced it.
pub struct Draft {
  priv engine : Engine
  priv mut snapshot : Json?
  priv components : Array[Component]
}

///|
/// Choose the representation used by text edits created by opgrain.
#derive(Eq, @debug.Debug)
pub(all) enum TextEncoding {
  Legacy
  Text0
}

///|
pub extend TextEncoding with Eq::{not_equal, equal}

///|
pub extend TextEncoding with @debug.Debug::{to_repr}

///|
pub fn Engine::draft(self : Engine, snapshot : Json?) -> Draft raise OpError {
  { engine: self, snapshot: snapshot.map(copy_checked_json), components: [], }
}

///|
pub fn Draft::snapshot(self : Draft) -> Json? {
  self.snapshot.map(copy_json)
}

///|
pub fn Draft::operation(self : Draft) -> Operation {
  { components: self.components.copy(), }
}

///|
fn child_path(
  path : Array[PathSegment],
  segment : PathSegment,
) -> Array[PathSegment] {
  let child = path.copy()
  child.push(segment)
  child
}

///|
fn Draft::record(self : Draft, component : Component) -> Unit raise OpError {
  let updated = self.engine.apply_component(self.snapshot, component)
  self.snapshot = updated
  self.components.push(component)
}

///|
/// Append an existing JSON0 operation atomically, checking its preimages.
pub fn Draft::append(
  self : Draft,
  operation : Operation,
) -> Unit raise VerificationError {
  let updated = self.engine.apply_verified(self.snapshot, operation)
  self.snapshot = updated
  for component in operation.components {
    self.components.push(component)
  }
}

///|
/// Read a value from the current document. An empty path denotes the root.
pub fn Draft::read(
  self : Draft,
  path : Array[PathSegment],
) -> Json raise OpError {
  copy_json(lookup_value(self.snapshot, path, path.length()))
}

///|
/// Insert or replace an object member or the entire root.
pub fn Draft::set(
  self : Draft,
  path : Array[PathSegment],
  value : Json,
) -> Unit raise OpError {
  let previous = object_preimage(self.snapshot, path)
  let next = copy_checked_json(value)
  if previous == Some(next) {
    return
  }
  self.record({
    path: path.copy(),
    action: ObjectEdit(Some(next), previous.map(copy_json)),
  })
}

///|
/// Remove an existing object member or the entire root.
pub fn Draft::remove(
  self : Draft,
  path : Array[PathSegment],
) -> Unit raise OpError {
  guard object_preimage(self.snapshot, path) is Some(previous) else {
    raise InvalidPath(path.copy(), "object member or root does not exist")
  }
  self.record({
    path: path.copy(),
    action: ObjectEdit(None, Some(copy_json(previous))),
  })
}

///|
pub fn Draft::insert_item(
  self : Draft,
  path : Array[PathSegment],
  value : Json,
) -> Unit raise OpError {
  ignore(list_position(self.snapshot, path, true))
  self.record({
    path: path.copy(),
    action: ListEdit(Some(copy_checked_json(value)), None),
  })
}

///|
pub fn Draft::replace_item(
  self : Draft,
  path : Array[PathSegment],
  value : Json,
) -> Unit raise OpError {
  let previous = list_preimage(self.snapshot, path)
  let next = copy_checked_json(value)
  if previous != next {
    self.record({
      path: path.copy(),
      action: ListEdit(Some(next), Some(copy_json(previous))),
    })
  }
}

///|
pub fn Draft::remove_item(
  self : Draft,
  path : Array[PathSegment],
) -> Unit raise OpError {
  let previous = list_preimage(self.snapshot, path)
  self.record({
    path: path.copy(),
    action: ListEdit(None, Some(copy_json(previous))),
  })
}

///|
/// Destination is the index in the list after the move.
pub fn Draft::move_item(
  self : Draft,
  path : Array[PathSegment],
  destination : Int32,
) -> Unit raise OpError {
  let (items, source) = list_position(self.snapshot, path, false)
  guard destination >= 0 && destination < items.length() else {
    raise InvalidPath(path.copy(), "list move destination out of bounds")
  }
  if destination != source {
    self.record({ path: path.copy(), action: Move(destination), })
  }
}

///|
pub fn Draft::add_number(
  self : Draft,
  path : Array[PathSegment],
  amount : Double,
) -> Unit raise OpError {
  let amount = checked_number(amount)
  self.record({ path: path.copy(), action: Add(amount), })
}

///|
fn text_components(
  path : Array[PathSegment],
  edits : Array[TextEdit],
  encoding : TextEncoding,
) -> Array[Component] {
  if edits.is_empty() {
    return []
  }
  match encoding {
    Text0 =>
      [
        {
          path: path.copy(),
          action: SubtypeEdit("text0", encode_text0(edits)),
        },
      ]
    Legacy =>
      edits.map(edit => {
        path: child_path(path, Index(edit.position)),
        action: LegacyText(edit.insert, edit.text),
      })
  }
}

///|
fn splice_edits(
  text : String,
  position : Int32,
  delete_count : Int32,
  inserted : String,
  path : Array[PathSegment],
) -> Array[TextEdit] raise OpError {
  guard position >= 0 &&
    position <= text.length() &&
    delete_count >= 0 &&
    delete_count <= text.length() - position else {
    raise InvalidPath(path.copy(), "text splice out of bounds")
  }
  let deleted = code_slice(text, position, position + delete_count)
  if deleted == inserted {
    return []
  }
  let edits = []
  if delete_count != 0 {
    edits.push({ position, insert: false, text: deleted, })
  }
  if !inserted.is_empty() {
    edits.push({ position, insert: true, text: inserted, })
  }
  edits
}

///|
/// Build a text edit with offsets and counts measured in UTF-16 code units.
/// Text0 overrides do not participate in this document-aware constructor.
pub fn Draft::splice_text(
  self : Draft,
  path : Array[PathSegment],
  position : Int32,
  delete_count : Int32,
  inserted : String,
  encoding~ : TextEncoding = Text0,
) -> Unit raise OpError {
  guard self.engine.subtypes.get("text0") is None else {
    raise SubtypeError("text0", "splice requires the built-in text0")
  }
  guard lookup_value(self.snapshot, path, path.length()) is String(text) else {
    raise InvalidPath(path.copy(), "text splice requires a string")
  }
  let edits = splice_edits(text, position, delete_count, inserted, path)
  for component in text_components(path, edits, encoding) {
    self.record(component)
  }
}
