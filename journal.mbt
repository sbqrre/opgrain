///|
priv struct Revision {
  operation : Operation
  snapshot : Snapshot
}

///|
/// Persistent checkpoints with absolute revision numbers and explicit compaction.
pub struct Journal {
  priv engine : Engine
  priv mut base : Snapshot
  priv mut base_revision : Int32
  priv mut entries : Array[Revision]
  priv mut busy : Bool
}

///|
pub fn Engine::journal(
  self : Engine,
  snapshot : Json?,
) -> Journal raise HistoryError {
  let base = Snapshot::new(snapshot) catch {
    error => raise InvalidHistorySnapshot(error)
  }
  self.journal_snapshot(base)
}

///|
pub fn Engine::journal_snapshot(self : Engine, snapshot : Snapshot) -> Journal {
  { engine: self, base: snapshot, base_revision: 0, entries: [], busy: false, }
}

///|
pub fn Journal::head(self : Journal) -> Int32 {
  self.base_revision + self.entries.length()
}

///|
/// The oldest revision still available for reads, rebasing and undo.
pub fn Journal::oldest_revision(self : Journal) -> Int32 {
  self.base_revision
}

///|
fn Journal::check_range(
  self : Journal,
  start : Int32,
  end : Int32,
) -> Unit raise HistoryError {
  let head = self.head()
  guard start >= self.base_revision && end >= start && end <= head else {
    raise InvalidRevisionRange(start, end, head)
  }
}

///|
fn Journal::checkpoint(self : Journal, revision : Int32) -> Snapshot {
  if revision == self.base_revision {
    self.base
  } else {
    self.entries[revision - self.base_revision - 1].snapshot
  }
}

///|
pub fn Journal::snapshot(self : Journal) -> Json? {
  self.checkpoint(self.head()).to_json()
}

///|
pub fn Journal::snapshot_at(
  self : Journal,
  revision : Int32,
) -> Json? raise HistoryError {
  self.snapshot_handle_at(revision).to_json()
}

///|
/// Return an immutable handle without materializing the document.
pub fn Journal::snapshot_handle_at(
  self : Journal,
  revision : Int32,
) -> Snapshot raise HistoryError {
  self.check_range(revision, revision)
  self.checkpoint(revision)
}

///|
fn Journal::operations_in(
  self : Journal,
  start : Int32,
  end : Int32,
) -> Array[Operation] {
  Array::makei(end - start, index => {
    self.entries[start - self.base_revision + index].operation
  })
}

///|
pub fn Journal::operations(
  self : Journal,
  start : Int32,
  end : Int32,
) -> Array[Operation] raise HistoryError {
  self.check_range(start, end)
  self.operations_in(start, end)
}

///|
fn Journal::enter(self : Journal) -> Unit raise HistoryError {
  guard !self.busy else { raise HistoryBusy }
  self.busy = true
}

///|
fn Journal::prepare_entries(
  self : Journal,
  operations : Array[Operation],
  phase : HistoryPhase,
  side : Side,
) -> Array[Revision] raise HistoryError {
  guard operations.length() <= 2147483647 - self.head() else {
    raise RevisionOverflow
  }
  let pending = []
  let mut snapshot = self.checkpoint(self.head())
  for index, operation in operations {
    snapshot = self.engine.apply_snapshot_verified(snapshot, operation) catch {
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
pub fn Journal::append(
  self : Journal,
  operation : Operation,
) -> Int32 raise HistoryError {
  self.append_all([operation])
}

///|
/// Record all revisions only after every operation succeeds.
pub fn Journal::append_all(
  self : Journal,
  operations : Array[Operation],
) -> Int32 raise HistoryError {
  self.enter()
  defer {
    self.busy = false
  }
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
  let merged = self.engine.merge_snapshot_histories(
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
  guard final_snapshot.value == merged.snapshot.value else {
    raise DivergentHistory(final_snapshot.to_json(), merged.snapshot())
  }
  self.save(pending)
}

///|
pub fn Journal::integrate(
  self : Journal,
  base : Int32,
  incoming : Array[Operation],
  text_encoding~ : TextEncoding? = None,
) -> Int32 raise HistoryError {
  self.enter()
  defer {
    self.busy = false
  }
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
    let op = self.entries[revision - self.base_revision - 1].operation
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
fn Journal::checked_inverse(
  self : Journal,
  start : Int32,
  end : Int32,
) -> Operation raise HistoryError {
  self.check_range(start, end)
  let inverse = self.inverse_since(start, end)
  let actual = self.engine.apply_snapshot_verified(
    self.checkpoint(end),
    inverse,
  ) catch {
    error => raise HistoryUndoFailed(end, error)
  }
  let expected = self.checkpoint(start)
  guard actual.value == expected.value else {
    raise HistoryUndoMismatch(expected.to_json(), actual.to_json())
  }
  inverse
}

///|
pub fn Journal::undo_operation(
  self : Journal,
  start : Int32,
  end : Int32,
) -> Operation raise HistoryError {
  self.enter()
  defer {
    self.busy = false
  }
  self.checked_inverse(start, end)
}

///|
pub fn Journal::revert(
  self : Journal,
  start : Int32,
  end : Int32,
  text_encoding~ : TextEncoding? = None,
) -> Int32 raise HistoryError {
  self.enter()
  defer {
    self.busy = false
  }
  let inverse = self.checked_inverse(start, end)
  if inverse.length() == 0 {
    return self.head()
  }
  self.save_merge(end, [inverse], text_encoding)
}

///|
/// Release checkpoints through a retained base revision without renumbering the head.
/// Snapshot handles already returned remain usable.
pub fn Journal::compact(
  self : Journal,
  through : Int32,
) -> Unit raise HistoryError {
  self.enter()
  defer {
    self.busy = false
  }
  self.check_range(self.base_revision, through)
  let retained = self.checkpoint(through)
  let offset = through - self.base_revision
  let entries = Array::makei(self.entries.length() - offset, i => {
    self.entries[offset + i]
  })
  self.base = retained
  self.base_revision = through
  self.entries = entries
}
