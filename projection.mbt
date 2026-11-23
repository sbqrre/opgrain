///|
#derive(Eq, @debug.Debug)
pub(all) enum ProjectionChangeKind {
  AddedMatch
  RemovedMatch
  ChangedMatch
}

///|
pub extend ProjectionChangeKind with Eq::{equal, not_equal}

///|
pub extend ProjectionChangeKind with @debug.Debug::{to_repr}

///|
pub struct ProjectionChange {
  priv path : Path
  priv kind : ProjectionChangeKind
  priv before : Json?
  priv after : Json?
}

///|
pub fn ProjectionChange::path(self : ProjectionChange) -> Path {
  self.path
}

///|
pub fn ProjectionChange::kind(self : ProjectionChange) -> ProjectionChangeKind {
  self.kind
}

///|
pub fn ProjectionChange::before(self : ProjectionChange) -> Json? {
  self.before.map(copy_json)
}

///|
pub fn ProjectionChange::after(self : ProjectionChange) -> Json? {
  self.after.map(copy_json)
}

///|
pub struct Projection {
  priv snapshot : Snapshot
  priv patterns : Array[PathPattern]
  priv limits : QueryLimits
  priv selection : Selection
}

///|
pub struct ProjectionUpdate {
  priv projection : Projection
  priv changes : Array[ProjectionChange]
}

///|
pub fn ProjectionUpdate::projection(self : ProjectionUpdate) -> Projection {
  self.projection
}

///|
pub fn ProjectionUpdate::changes(
  self : ProjectionUpdate,
) -> Array[ProjectionChange] {
  self.changes.copy()
}

///|
#derive(@debug.Debug)
pub(all) suberror ProjectionError {
  ProjectionQuery(QueryError)
  ProjectionPath(OpError)
  ProjectionApply(VerificationError)
  OverlappingSelection(Path, Path)
  SelectionCallback(Int32, OpError)
  SelectionUndo(UndoError)
}

///|
pub extend ProjectionError with @debug.Debug::{to_repr}

///|
pub fn Snapshot::project(
  self : Snapshot,
  patterns : Array[PathPattern],
  limits~ : QueryLimits = QueryLimits::default(),
) -> Projection raise QueryError {
  let patterns = patterns.copy()
  let selection = self.select(patterns, limits~)
  { snapshot: self, patterns, limits, selection, }
}

///|
pub fn Projection::snapshot(self : Projection) -> Snapshot {
  self.snapshot
}

///|
pub fn Projection::selection(self : Projection) -> Selection {
  self.selection
}

///|
pub fn Projection::patterns(self : Projection) -> Array[PathPattern] {
  self.patterns.copy()
}

///|
fn path_identity(path : Path) -> String {
  stringify_json(path.to_json()) catch {
    _ => abort("checked path encoding")
  }
}

///|
/// Compare matches by their JSON0 path, rather than by application-specific item IDs.
pub fn Projection::refresh(
  self : Projection,
  snapshot : Snapshot,
) -> ProjectionUpdate raise ProjectionError {
  let next = snapshot.project(self.patterns, limits=self.limits) catch {
    error => raise ProjectionQuery(error)
  }
  let previous : Map[String, Path] = Map([])
  let current : Map[String, Path] = Map([])
  for path in self.selection.paths {
    previous[path_identity(path)] = path
  }
  for path in next.selection.paths {
    current[path_identity(path)] = path
  }
  let changes : Array[ProjectionChange] = []
  for path in self.selection.paths {
    let key = path_identity(path)
    let before = guard_value(self.snapshot, path)
    if !current.contains(key) {
      changes.push({ path, kind: RemovedMatch, before, after: None, })
    } else {
      let after = guard_value(snapshot, path)
      if !same_optional_json(before, after) {
        changes.push({ path, kind: ChangedMatch, before, after, })
      }
    }
  }
  for path in next.selection.paths {
    if !previous.contains(path_identity(path)) {
      changes.push({
        path,
        kind: AddedMatch,
        before: None,
        after: guard_value(snapshot, path),
      })
    }
  }
  { projection: next, changes, }
}

///|
pub fn Engine::update_projection(
  self : Engine,
  projection : Projection,
  operation : Operation,
) -> ProjectionUpdate raise ProjectionError {
  let snapshot = self.apply_snapshot_verified(projection.snapshot, operation) catch {
    error => raise ProjectionApply(error)
  }
  projection.refresh(snapshot)
}

///|
/// Map detached matched values from the original snapshot. Overlapping matches
/// are rejected before callbacks run so every replacement has an unambiguous preimage.
pub fn Engine::edit_selection(
  self : Engine,
  selection : Selection,
  update : (Path, Json) -> Json raise OpError,
) -> UndoableEdit raise ProjectionError {
  for index, path in selection.paths {
    for other in selection.paths[index + 1:] {
      if path.starts_with(other) || other.starts_with(path) {
        raise OverlappingSelection(path, other)
      }
    }
  }
  let components = []
  for index, path in selection.paths {
    let before = guard_value(selection.snapshot, path).unwrap()
    let after = update(path, copy_json(before)) catch {
      error => raise SelectionCallback(index, error)
    }
    let after = copy_checked_json(after) catch {
      error => raise SelectionCallback(index, error)
    }
    if same_json(before, after) {
      continue
    }
    let action = match path.last() {
      Some(Index(_)) => ListEdit(Some(after), Some(before))
      _ => ObjectEdit(Some(after), Some(before))
    }
    components.push(Component::{ path: path.segments(), action, })
  }
  self.prepare_edit(selection.snapshot, { components, }) catch {
    ForwardRejected(error) => raise ProjectionApply(error)
    error => raise SelectionUndo(error)
  }
}
