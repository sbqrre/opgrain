///|
priv struct UndoEntry {
  label : String
  operation : Operation
}

///|
#derive(@debug.Debug)
pub(all) suberror UndoHistoryError {
  UndoHistoryBusy
  InvalidUndoCapacity(Int32)
  NothingToUndo
  NothingToRedo
  UndoPreparation(UndoError)
  UndoRebase(Int32, OpError)
  UndoReplay(Int32, VerificationError)
  ExternalEditRejected(VerificationError)
  UndoComposition(CompositionError)
}

///|
pub extend UndoHistoryError with @debug.Debug::{to_repr}

///|
/// A local undo/redo stack. Pending inverses are expressed in reverse stack order.
pub struct UndoHistory {
  priv engine : Engine
  priv mut snapshot : Snapshot
  priv mut undo : Array[UndoEntry]
  priv mut redo : Array[UndoEntry]
  priv capacity : Int32
  priv mut busy : Bool
  priv mut joinable : Bool
}

///|
pub fn Engine::undo_history(
  self : Engine,
  snapshot : Snapshot,
  capacity~ : Int32 = 1000,
) -> UndoHistory raise UndoHistoryError {
  guard capacity >= 0 else { raise InvalidUndoCapacity(capacity) }
  {
    engine: self.fork(),
    snapshot,
    undo: [],
    redo: [],
    capacity,
    busy: false,
    joinable: false,
  }
}

///|
pub fn UndoHistory::snapshot(self : UndoHistory) -> Snapshot {
  self.snapshot
}

///|
pub fn UndoHistory::undo_count(self : UndoHistory) -> Int32 {
  self.undo.length()
}

///|
pub fn UndoHistory::redo_count(self : UndoHistory) -> Int32 {
  self.redo.length()
}

///|
/// Labels are returned from the next available action to the oldest action.
pub fn UndoHistory::undo_labels(self : UndoHistory) -> Array[String] {
  let labels = self.undo.map(entry => entry.label)
  labels.rev_in_place()
  labels
}

///|
pub fn UndoHistory::redo_labels(self : UndoHistory) -> Array[String] {
  let labels = self.redo.map(entry => entry.label)
  labels.rev_in_place()
  labels
}

///|
fn UndoHistory::enter(self : UndoHistory) -> Unit raise UndoHistoryError {
  guard !self.busy else { raise UndoHistoryBusy }
  self.busy = true
}

///|
fn retain_undo_capacity(
  entries : Array[UndoEntry],
  capacity : Int32,
) -> Array[UndoEntry] {
  if entries.length() <= capacity {
    entries
  } else {
    entries[entries.length() - capacity:].to_owned()
  }
}

///|
/// Record a user action. Grouping is explicit and never crosses an external edit.
pub fn UndoHistory::record(
  self : UndoHistory,
  operation : Operation,
  label~ : String = "",
  join_previous~ : Bool = false,
) -> Snapshot raise UndoHistoryError {
  self.enter()
  defer {
    self.busy = false
  }
  let edit = self.engine.prepare_edit(self.snapshot, operation) catch {
    error => raise UndoPreparation(error)
  }
  let pending = self.undo.copy()
  if operation.length() > 0 && self.capacity > 0 {
    if join_previous && self.joinable && pending.pop() is Some(previous) {
      let combined = self.engine.compose_verified(edit.snapshot, [
        edit.inverse,
        previous.operation,
      ]) catch {
        error => raise UndoComposition(error)
      }
      pending.push({
        label: if label == "" {
          previous.label
        } else {
          label
        },
        operation: combined.operation(),
      })
    } else {
      pending.push({ label, operation: edit.inverse, })
    }
  }
  self.snapshot = edit.snapshot
  self.undo = retain_undo_capacity(pending, self.capacity)
  if operation.length() > 0 {
    self.redo = []
    self.joinable = true
  }
  self.snapshot
}

///|
fn UndoHistory::execute(
  self : UndoHistory,
  is_undo : Bool,
) -> Snapshot raise UndoHistoryError {
  self.enter()
  defer {
    self.busy = false
  }
  let source = if is_undo { self.undo } else { self.redo }
  guard source.last() is Some(entry) else {
    if is_undo {
      raise NothingToUndo
    } else {
      raise NothingToRedo
    }
  }
  let edit = self.engine.prepare_edit(self.snapshot, entry.operation) catch {
    error => raise UndoPreparation(error)
  }
  let remaining = source[:source.length() - 1].to_owned()
  let destination = if is_undo { self.redo.copy() } else { self.undo.copy() }
  destination.push({ label: entry.label, operation: edit.inverse, })
  self.snapshot = edit.snapshot
  self.joinable = false
  if is_undo {
    self.undo = remaining
    self.redo = retain_undo_capacity(destination, self.capacity)
  } else {
    self.redo = remaining
    self.undo = retain_undo_capacity(destination, self.capacity)
  }
  self.snapshot
}

///|
pub fn UndoHistory::undo(self : UndoHistory) -> Snapshot raise UndoHistoryError {
  self.execute(true)
}

///|
pub fn UndoHistory::redo(self : UndoHistory) -> Snapshot raise UndoHistoryError {
  self.execute(false)
}

///|
fn Engine::rebase_undo_entries(
  self : Engine,
  snapshot : Snapshot,
  entries : Array[UndoEntry],
  external : Operation,
) -> Array[UndoEntry] raise UndoHistoryError {
  let pending = entries.copy()
  let mut across = external
  let mut checkpoint = snapshot
  for offset in 0..<pending.length() {
    let index = pending.length() - offset - 1
    let entry = pending[index]
    let (inverse, next_external) = self.transform_x(entry.operation, across) catch {
      error => raise UndoRebase(index, error)
    }
    checkpoint = self.apply_snapshot_verified(checkpoint, inverse) catch {
      error => raise UndoReplay(index, error)
    }
    pending[index] = { ..entry, operation: inverse, }
    across = next_external
  }
  pending
}

///|
/// Transform both pending stacks against an already rebased external operation.
/// No network protocol is implied. Invalid transformed stacks reject atomically.
pub fn UndoHistory::apply_external(
  self : UndoHistory,
  operation : Operation,
) -> Snapshot raise UndoHistoryError {
  self.enter()
  defer {
    self.busy = false
  }
  let snapshot = self.engine.apply_snapshot_verified(self.snapshot, operation) catch {
    error => raise ExternalEditRejected(error)
  }
  let undo = self.engine.rebase_undo_entries(snapshot, self.undo, operation)
  let redo = self.engine.rebase_undo_entries(snapshot, self.redo, operation)
  self.snapshot = snapshot
  self.joinable = false
  self.undo = undo
  self.redo = redo
  self.snapshot
}

///|
/// Clear undo metadata while retaining the current immutable document.
pub fn UndoHistory::clear(self : UndoHistory) -> Unit raise UndoHistoryError {
  self.enter()
  defer {
    self.busy = false
  }
  self.undo = []
  self.redo = []
  self.joinable = false
}

///|
/// Return the next inverse without consuming it. Payload ownership stays internal.
pub fn UndoHistory::peek_undo(self : UndoHistory) -> Operation? {
  self.undo.last().map(entry => entry.operation)
}

///|
pub fn UndoHistory::peek_redo(self : UndoHistory) -> Operation? {
  self.redo.last().map(entry => entry.operation)
}
