///|
/// Fork registry membership so subsequent registrations can be managed independently.
pub fn Engine::fork(self : Engine) -> Engine {
  { subtypes: self.subtypes.copy(), }
}

///|
/// Start a draft from an already validated immutable checkpoint.
pub fn Engine::draft_snapshot(self : Engine, snapshot : Snapshot) -> Draft {
  { engine: self, snapshot: snapshot.value, components: [], busy: false, }
}

///|
pub fn Draft::snapshot_handle(self : Draft) -> Snapshot {
  { value: self.snapshot, }
}

///|
/// Edit an isolated candidate and record the whole delta after the callback succeeds.
/// Reentrant writes to this draft are rejected while the callback is running.
pub fn Draft::transaction(
  self : Draft,
  edit : (Draft) -> Unit raise OpError,
) -> Operation raise OpError {
  guard !self.busy else { raise DraftBusy }
  self.busy = true
  defer {
    self.busy = false
  }
  let candidate = self.engine.draft_snapshot(self.snapshot_handle())
  edit(candidate)
  let operation = candidate.operation()
  self.snapshot = candidate.snapshot
  for component in operation.components {
    self.components.push(component)
  }
  operation
}

///|
/// Insert and remove several list items as one atomic transaction.
pub fn Draft::splice_items(
  self : Draft,
  path : Array[PathSegment],
  position : Int32,
  delete_count : Int32,
  values : Array[Json],
) -> Unit raise OpError {
  let items = require_list(
    lookup_value(self.snapshot, path, path.length()),
    path,
  )
  guard position >= 0 &&
    position <= items.length() &&
    delete_count >= 0 &&
    delete_count <= items.length() - position else {
    raise InvalidPath(path.copy(), "list splice out of bounds")
  }
  let values = values.map(copy_checked_json)
  ignore(
    self.transaction(candidate => {
      let common = Int32::min(delete_count, values.length())
      for index in 0..<common {
        candidate.replace_item(
          child_path(path, Index(position + index)),
          values[index],
        )
      }
      for _ in common..<delete_count {
        candidate.remove_item(child_path(path, Index(position + common)))
      }
      for index in common..<values.length() {
        candidate.insert_item(
          child_path(path, Index(position + index)),
          values[index],
        )
      }
    }),
  )
}

///|
/// Delegate a typed path and detached payload to a registered subtype.
pub fn Draft::edit_subtype(
  self : Draft,
  path : Array[PathSegment],
  name : String,
  payload : Json,
) -> Unit raise OpError {
  self.record({
    path: path.copy(),
    action: SubtypeEdit(name, copy_checked_json(payload)),
  })
}
