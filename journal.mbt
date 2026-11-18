///|
priv struct Revision {
  operation : Operation
  snapshot : Json?
}

///|
/// An in-memory sequence with one checkpoint per applied operation.
pub struct Journal {
  priv engine : Engine
  priv base : Json?
  priv entries : Array[Revision]
}

///|
pub fn Engine::journal(
  self : Engine,
  snapshot : Json?,
) -> Journal raise HistoryError {
  let base = snapshot.map(copy_checked_json) catch {
    error => raise InvalidHistorySnapshot(error)
  }
  { engine: self, base, entries: [], }
}

///|
pub fn Journal::head(self : Journal) -> Int32 {
  self.entries.length()
}

///|
fn Journal::check_range(
  self : Journal,
  start : Int32,
  end : Int32,
) -> Unit raise HistoryError {
  let head = self.head()
  guard start >= 0 && end >= start && end <= head else {
    raise InvalidRevisionRange(start, end, head)
  }
}

///|
fn Journal::checkpoint(self : Journal, revision : Int32) -> Json? {
  if revision == 0 {
    self.base
  } else {
    self.entries[revision - 1].snapshot
  }
}

///|
pub fn Journal::snapshot(self : Journal) -> Json? {
  self.checkpoint(self.head()).map(copy_json)
}

///|
pub fn Journal::snapshot_at(
  self : Journal,
  revision : Int32,
) -> Json? raise HistoryError {
  self.check_range(revision, revision)
  self.checkpoint(revision).map(copy_json)
}

///|
fn Journal::operations_in(
  self : Journal,
  start : Int32,
  end : Int32,
) -> Array[Operation] {
  Array::makei(end - start, index => self.entries[start + index].operation)
}

///|
/// Return the operations after start up to and including end.
pub fn Journal::operations(
  self : Journal,
  start : Int32,
  end : Int32,
) -> Array[Operation] raise HistoryError {
  self.check_range(start, end)
  self.operations_in(start, end)
}

///|
fn Journal::prepare_entries(
  self : Journal,
  operations : Array[Operation],
  phase : HistoryPhase,
  side : Side,
) -> Array[Revision] raise HistoryError {
  let pending = []
  let mut snapshot = self.checkpoint(self.head())
  for index, operation in operations {
    snapshot = self.engine.apply_verified(snapshot, operation) catch {
      error => raise HistoryApplyFailed(phase, side, index, error)
    }
    pending.push({ operation, snapshot, })
  }
  pending
}

///|
fn Journal::save(self : Journal, pending : Array[Revision]) -> Int32 {
  for entry in pending {
    self.entries.push(entry)
  }
  self.head()
}

///|
/// Record a verified operation and return the new head revision.
pub fn Journal::append(
  self : Journal,
  operation : Operation,
) -> Int32 raise HistoryError {
  self.append_all([operation])
}

///|
/// Validate the complete batch before recording any of its revisions.
pub fn Journal::append_all(
  self : Journal,
  operations : Array[Operation],
) -> Int32 raise HistoryError {
  self.save(self.prepare_entries(operations, Original, Left))
}

///|
fn Journal::save_merge(
  self : Journal,
  base : Int32,
  incoming : Array[Operation],
  text_encoding : TextEncoding?,
) -> Int32 raise HistoryError {
  let original = self.operations_in(base, self.head())
  let merged = self.engine.merge_histories(
    self.checkpoint(base),
    original,
    incoming,
    text_encoding~,
  )
  let pending = self.prepare_entries(
    merged.histories.right_after_left,
    Transformed,
    Right,
  )
  let final_snapshot = match pending.last() {
    Some(entry) => entry.snapshot
    None => self.checkpoint(self.head())
  }
  guard final_snapshot == merged.snapshot else {
    raise DivergentHistory(final_snapshot.map(copy_json), merged.snapshot())
  }
  self.save(pending)
}

///|
/// Rebase incoming operations onto the head, giving existing history left priority.
pub fn Journal::integrate(
  self : Journal,
  base : Int32,
  incoming : Array[Operation],
  text_encoding~ : TextEncoding? = None,
) -> Int32 raise HistoryError {
  self.check_range(base, self.head())
  self.save_merge(base, incoming, text_encoding)
}

///|
fn Journal::inverse_since(
  self : Journal,
  start : Int32,
  end : Int32,
) -> Operation raise HistoryError {
  let components = []
  for revision = end; revision > start; revision = revision - 1 {
    let op = self.entries[revision - 1].operation
    let reversed = self.engine.invert(op) catch {
      error => raise HistoryInvertFailed(revision, error)
    }
    for component in reversed.components {
      components.push(component)
    }
  }
  { components, }
}

///|
/// Construct an inverse for a range and check it against the original checkpoints.
pub fn Journal::undo_operation(
  self : Journal,
  start : Int32,
  end : Int32,
) -> Operation raise HistoryError {
  self.check_range(start, end)
  let inverse = self.inverse_since(start, end)
  let actual = self.engine.apply_verified(self.checkpoint(end), inverse) catch {
    error => raise HistoryUndoFailed(end, error)
  }
  let expected = self.checkpoint(start)
  guard actual == expected else {
    raise HistoryUndoMismatch(expected.map(copy_json), actual)
  }
  inverse
}

///|
/// Undo a revision range through later edits and append it as a new operation.
pub fn Journal::revert(
  self : Journal,
  start : Int32,
  end : Int32,
  text_encoding~ : TextEncoding? = None,
) -> Int32 raise HistoryError {
  let inverse = self.undo_operation(start, end)
  if inverse.length() == 0 {
    return self.head()
  }
  self.save_merge(end, [inverse], text_encoding)
}
