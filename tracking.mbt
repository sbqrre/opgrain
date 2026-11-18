///|
#derive(Eq, @debug.Debug)
pub(all) enum InsertionAffinity {
  BeforeInsertion
  AfterInsertion
}

///|
pub extend InsertionAffinity with Eq::{not_equal, equal}

///|
pub extend InsertionAffinity with @debug.Debug::{to_repr}

///|
#derive(Eq, @debug.Debug)
pub(all) struct TextPosition {
  offset : Int32
  affinity : InsertionAffinity
}

///|
pub extend TextPosition with Eq::{not_equal, equal}

///|
pub extend TextPosition with @debug.Debug::{to_repr}

///|
#derive(Eq, @debug.Debug)
pub(all) enum Location {
  Node(Array[PathSegment])
  Cursor(Array[PathSegment], TextPosition)
  TextRange(Array[PathSegment], TextPosition, TextPosition)
}

///|
pub extend Location with Eq::{not_equal, equal}

///|
pub extend Location with @debug.Debug::{to_repr}

///|
#derive(@debug.Debug)
pub(all) suberror TrackingError {
  InvalidLocation(Int32, Array[PathSegment], OpError)
  TrackingSnapshotFailed(OpError)
  TrackingApplyFailed(Int32, VerificationError)
}

///|
pub extend TrackingError with @debug.Debug::{to_repr}

///|
#derive(Eq, @debug.Debug)
pub(all) enum LossReason {
  ListItemRemoved
  NodeOverwritten
  OpaqueSubtype
}

///|
pub extend LossReason with Eq::{not_equal, equal}

///|
pub extend LossReason with @debug.Debug::{to_repr}

///|
#derive(Eq, @debug.Debug)
pub(all) struct LocationLoss {
  batch : Int32
  component : Int32
  reason : LossReason
}

///|
pub extend LocationLoss with Eq::{not_equal, equal}

///|
pub extend LocationLoss with @debug.Debug::{to_repr}

///|
pub struct TrackedApply {
  priv snapshot : Json?
  priv locations : Array[Location?]
  priv losses : Array[LocationLoss?]
}

///|
fn Location::path(self : Location) -> Array[PathSegment] {
  match self {
    Node(path) | Cursor(path, _) | TextRange(path, _, _) => path
  }
}

///|
fn Location::with_path(self : Location, path : Array[PathSegment]) -> Location {
  match self {
    Node(_) => Node(path)
    Cursor(_, cursor) => Cursor(path, cursor)
    TextRange(_, start, end) => TextRange(path, start, end)
  }
}

///|
fn Location::detached(self : Location) -> Location {
  self.with_path(self.path().copy())
}

///|
pub fn TrackedApply::snapshot(self : TrackedApply) -> Json? {
  self.snapshot.map(copy_json)
}

///|
/// Results follow input order. None means the location no longer has an anchor.
pub fn TrackedApply::locations(self : TrackedApply) -> Array[Location?] {
  self.locations.map(location => location.map(Location::detached))
}

///|
/// The first invalidating component for each location, using zero-based indices.
pub fn TrackedApply::losses(self : TrackedApply) -> Array[LocationLoss?] {
  self.losses.copy()
}

///|
fn validate_text_span(
  value : Json,
  path : Array[PathSegment],
  start : Int32,
  end : Int32,
) -> Unit raise OpError {
  guard value is String(text) else {
    raise InvalidPath(path.copy(), "text location requires a string")
  }
  guard start >= 0 && end >= start && end <= text.length() else {
    raise InvalidPath(path.copy(), "text location out of bounds")
  }
}

///|
fn validate_location(
  snapshot : Json?,
  location : Location,
) -> Unit raise OpError {
  let path = location.path()
  let value = lookup_value(snapshot, path, path.length())
  match location {
    Node(_) => ()
    Cursor(_, position) =>
      validate_text_span(value, path, position.offset, position.offset)
    TextRange(_, start, end) =>
      validate_text_span(value, path, start.offset, end.offset)
  }
}

///|
priv enum LocationChange {
  NoChange
  Discard(Array[PathSegment], LossReason)
  InsertItem(Array[PathSegment], Int32)
  RemoveItem(Array[PathSegment], Int32)
  MoveItem(Array[PathSegment], Int32, Int32)
  EditText(Array[PathSegment], Array[TextEdit])
}

///|
fn LocationChange::loss_reason(self : LocationChange) -> LossReason? {
  match self {
    Discard(_, reason) => Some(reason)
    RemoveItem(_, _) => Some(ListItemRemoved)
    _ => None
  }
}

///|
fn parent_path(path : Array[PathSegment]) -> Array[PathSegment] {
  let parent = path.copy()
  ignore(parent.pop())
  parent
}

///|
fn Engine::location_change(
  self : Engine,
  component : Component,
) -> LocationChange raise OpError {
  let { path, action, } = component
  match action {
    ListEdit(Some(_), None) if path.last() is Some(Index(index)) =>
      InsertItem(parent_path(path), index)
    ListEdit(None, Some(_)) if path.last() is Some(Index(index)) =>
      RemoveItem(parent_path(path), index)
    Move(destination) if path.last() is Some(Index(index)) =>
      MoveItem(parent_path(path), index, destination)
    LegacyText(_, _) => {
      let (target, edit) = legacy_edit(component)
      if self.subtypes.contains("text0") {
        Discard(target, OpaqueSubtype)
      } else {
        EditText(target, [edit])
      }
    }
    SubtypeEdit("text0", payload) if !self.subtypes.contains("text0") =>
      EditText(path, decode_text0(payload))
    ObjectEdit(_, _) | ListEdit(_, _) => Discard(path, NodeOverwritten)
    SubtypeEdit(_, _) => Discard(path, OpaqueSubtype)
    _ => NoChange
  }
}

///|
fn has_prefix(path : Array[PathSegment], prefix : Array[PathSegment]) -> Bool {
  if prefix.length() > path.length() {
    return false
  }
  for i, segment in prefix {
    if path[i] != segment {
      return false
    }
  }
  true
}

///|
fn location_item(location : Location, container : Array[PathSegment]) -> Int32? {
  let path = location.path()
  let depth = container.length()
  if depth < path.length() &&
    has_prefix(path, container) &&
    path[depth] is Index(index) {
    Some(index)
  } else {
    None
  }
}

///|
fn Location::at_list_index(
  self : Location,
  depth : Int32,
  index : Int32,
) -> Location {
  let path = self.path().copy()
  path[depth] = Index(index)
  self.with_path(path)
}

///|
fn moved_item(current : Int32, source : Int32, destination : Int32) -> Int32 {
  if current == source {
    destination
  } else if source < current && current <= destination {
    current - 1
  } else if destination <= current && current < source {
    current + 1
  } else {
    current
  }
}

///|
fn move_text_position(position : TextPosition, edit : TextEdit) -> TextPosition {
  let size = edit.text.length()
  let offset = position.offset
  if offset < edit.position {
    return position
  }
  if edit.insert {
    if offset > edit.position || position.affinity == AfterInsertion {
      return { ..position, offset: offset + size, }
    }
    return position
  }
  { ..position, offset: Int32::max(edit.position, offset - size), }
}

///|
fn Location::after_text(
  self : Location,
  path : Array[PathSegment],
  edits : Array[TextEdit],
) -> Location {
  if self.path() != path {
    return self
  }
  match self {
    Node(_) => self
    Cursor(_, cursor) => {
      let mut cursor = cursor
      for edit in edits {
        cursor = move_text_position(cursor, edit)
      }
      Cursor(path, cursor)
    }
    TextRange(_, start, end) => {
      let mut start = start
      let mut end = end
      for edit in edits {
        start = move_text_position(start, edit)
        end = move_text_position(end, edit)
        if start.offset > end.offset {
          // After a crossed collapsed selection, keep the caret at its start.
          end = { ..end, offset: start.offset, }
        }
      }
      TextRange(path, start, end)
    }
  }
}

///|
fn Location::after_change(
  self : Location,
  change : LocationChange,
) -> Location? {
  match change {
    Discard(path, _) if has_prefix(self.path(), path) => None
    InsertItem(path, at) if location_item(self, path) is Some(old) && old >= at =>
      Some(self.at_list_index(path.length(), old + 1))
    RemoveItem(path, at) if location_item(self, path) is Some(old) =>
      if old == at {
        None
      } else if old > at {
        Some(self.at_list_index(path.length(), old - 1))
      } else {
        Some(self)
      }
    MoveItem(path, from, to) if location_item(self, path) is Some(old) => {
      let index = moved_item(old, from, to)
      if index == old {
        Some(self)
      } else {
        Some(self.at_list_index(path.length(), index))
      }
    }
    EditText(path, edits) => Some(self.after_text(path, edits))
    _ => Some(self)
  }
}

///|
/// Apply a verified JSON0 operation and follow nodes and UTF-16 text positions.
pub fn Engine::apply_tracked(
  self : Engine,
  snapshot : Json?,
  operation : Operation,
  locations : Array[Location],
) -> TrackedApply raise TrackingError {
  self.apply_tracked_batches(snapshot, [operation], locations)
}

///|
/// Follow locations through sequential batches without composing their components.
pub fn Engine::apply_tracked_batches(
  self : Engine,
  snapshot : Json?,
  operations : Array[Operation],
  locations : Array[Location],
) -> TrackedApply raise TrackingError {
  let mut updated = snapshot.map(copy_checked_json) catch {
    error => raise TrackingSnapshotFailed(error)
  }
  let current = []
  for index, location in locations {
    validate_location(updated, location) catch {
      error => raise InvalidLocation(index, location.path().copy(), error)
    }
    current.push(Some(location.detached()))
  }
  let losses = Array::make(locations.length(), None)
  let mut active = current.length()
  for batch, operation in operations {
    for index, component in operation.components {
      updated = self.verify_component(updated, component, index) catch {
        error => raise TrackingApplyFailed(batch, error)
      }
      if active == 0 {
        continue
      }
      let effect = self.location_change(component) catch {
        error =>
          raise TrackingApplyFailed(
            batch,
            ComponentFailed(index, component.path.copy(), error),
          )
      }
      if effect is NoChange {
        continue
      }
      for i, location in current {
        if location is Some(location) {
          let next = location.after_change(effect)
          if next is None && effect.loss_reason() is Some(reason) {
            losses[i] = Some({ batch, component: index, reason, })
            active -= 1
          }
          current[i] = next
        }
      }
    }
  }
  { snapshot: updated, locations: current, losses, }
}
