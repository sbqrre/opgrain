///|
#derive(@debug.Debug)
pub(all) suberror RebaseError {
  RebaseBusy
  RebaseRange(Int32, Int32)
  RebaseOverflow
  PendingApply(Int32, VerificationError)
  RebaseMerge(HistoryError)
  StaleRebasePreview
}

///|
pub extend RebaseError with @debug.Debug::{to_repr}

///|
/// Local pending operations above a confirmed immutable base, without transport.
pub struct RebaseBuffer {
  priv engine : Engine
  priv mut base : Snapshot
  priv mut entries : Array[Revision]
  priv mut generation : Int32
  priv mut busy : Bool
}

///|
pub struct RebasePreview {
  priv owner : RebaseBuffer
  priv generation : Int32
  priv base : Snapshot
  priv entries : Array[Revision]
  priv external_after_pending : Array[Operation]
}

///|
pub fn Engine::rebase_buffer(self : Engine, base : Snapshot) -> RebaseBuffer {
  { engine: self.fork(), base, entries: [], generation: 0, busy: false, }
}

///|
pub fn RebaseBuffer::base(self : RebaseBuffer) -> Snapshot {
  self.base
}

///|
pub fn RebaseBuffer::length(self : RebaseBuffer) -> Int32 {
  self.entries.length()
}

///|
pub fn RebaseBuffer::snapshot(self : RebaseBuffer) -> Snapshot {
  self.entries.last().map(entry => entry.snapshot).unwrap_or(self.base)
}

///|
pub fn RebaseBuffer::operations(self : RebaseBuffer) -> Array[Operation] {
  self.entries.map(entry => entry.operation)
}

///|
fn RebaseBuffer::enter(self : RebaseBuffer) -> Unit raise RebaseError {
  guard !self.busy else { raise RebaseBusy }
  self.busy = true
}

///|
fn RebaseBuffer::next_generation(
  self : RebaseBuffer,
) -> Int32 raise RebaseError {
  guard self.generation < 2147483647 else { raise RebaseOverflow }
  self.generation + 1
}

///|
fn Engine::pending_entries(
  self : Engine,
  snapshot : Snapshot,
  operations : Array[Operation],
) -> Array[Revision] raise RebaseError {
  let entries = []
  let mut current = snapshot
  for index, operation in operations {
    current = self.apply_snapshot_verified(current, operation) catch {
      error => raise PendingApply(index, error)
    }
    entries.push(Revision::{ operation, snapshot: current, })
  }
  entries
}

///|
pub fn RebaseBuffer::append_all(
  self : RebaseBuffer,
  operations : Array[Operation],
) -> Snapshot raise RebaseError {
  self.enter()
  defer {
    self.busy = false
  }
  let generation = self.next_generation()
  guard operations.length() <= 2147483647 - self.length() else {
    raise RebaseOverflow
  }
  let pending = self.engine.pending_entries(self.snapshot(), operations)
  let entries = self.entries.copy()
  entries.append(pending)
  self.entries = entries
  self.generation = generation
  self.snapshot()
}

///|
pub fn RebaseBuffer::append(
  self : RebaseBuffer,
  operation : Operation,
) -> Snapshot raise RebaseError {
  self.append_all([operation])
}

///|
/// Move an accepted prefix into the base, preserving the visible document.
pub fn RebaseBuffer::confirm_prefix(
  self : RebaseBuffer,
  count : Int32,
) -> Snapshot raise RebaseError {
  self.enter()
  defer {
    self.busy = false
  }
  guard count >= 0 && count <= self.length() else {
    raise RebaseRange(count, self.length())
  }
  let generation = self.next_generation()
  if count > 0 {
    self.base = self.entries[count - 1].snapshot
  }
  self.entries = self.entries[count:].to_owned()
  self.generation = generation
  self.snapshot()
}

///|
/// External batches must be based on base(), not on the visible pending snapshot.
pub fn RebaseBuffer::preview(
  self : RebaseBuffer,
  external : Array[Operation],
  text_encoding~ : TextEncoding? = None,
) -> RebasePreview raise RebaseError {
  self.enter()
  defer {
    self.busy = false
  }
  let merged = self.engine.merge_snapshot_histories(
    self.base,
    self.operations(),
    external,
    text_encoding~,
  ) catch {
    error => raise RebaseMerge(error)
  }
  let base_entries = self.engine.pending_entries(self.base, external)
  let base = base_entries
    .last()
    .map(entry => entry.snapshot)
    .unwrap_or(self.base)
  let entries = self.engine.pending_entries(
    base,
    merged.histories.left_after_right,
  )
  let head = entries.last().map(entry => entry.snapshot).unwrap_or(base)
  guard head.value == merged.snapshot.value else {
    raise RebaseMerge(DivergentHistory(head.to_json(), merged.snapshot()))
  }
  {
    owner: self,
    generation: self.generation,
    base,
    entries,
    external_after_pending: merged.histories.right_after_left.copy(),
  }
}

///|
pub fn RebasePreview::base(self : RebasePreview) -> Snapshot {
  self.base
}

///|
pub fn RebasePreview::snapshot(self : RebasePreview) -> Snapshot {
  self.entries.last().map(entry => entry.snapshot).unwrap_or(self.base)
}

///|
pub fn RebasePreview::pending(self : RebasePreview) -> Array[Operation] {
  self.entries.map(entry => entry.operation)
}

///|
pub fn RebasePreview::external_after_pending(
  self : RebasePreview,
) -> Array[Operation] {
  self.external_after_pending.copy()
}

///|
pub fn RebaseBuffer::accept(
  self : RebaseBuffer,
  preview : RebasePreview,
) -> Snapshot raise RebaseError {
  self.enter()
  defer {
    self.busy = false
  }
  guard physical_equal(self, preview.owner) &&
    self.generation == preview.generation else {
    raise StaleRebasePreview
  }
  let generation = self.next_generation()
  self.base = preview.base
  self.entries = preview.entries.copy()
  self.generation = generation
  self.snapshot()
}
