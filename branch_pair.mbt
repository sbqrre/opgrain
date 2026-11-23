///|
priv struct BranchLane {
  label : String
  entries : Array[Revision]
}

///|
#derive(@debug.Debug)
pub(all) suberror BranchError {
  InvalidBranchLabels
  BranchBusy
  BranchApply(Side, Int32, VerificationError)
  BranchHistory(HistoryError)
  BranchRange(Side, Int32, Int32)
  StaleBranchPreview
  BranchRevisionOverflow
}

///|
pub extend BranchError with @debug.Debug::{to_repr}

///|
/// Two local sequential histories sharing an immutable checkpoint.
pub struct BranchPair {
  priv engine : Engine
  priv mut base : Snapshot
  priv mut left : BranchLane
  priv mut right : BranchLane
  priv mut generation : Int32
  priv mut busy : Bool
}

///|
pub struct BranchPreview {
  priv owner : BranchPair
  priv generation : Int32
  priv left_count : Int32
  priv right_count : Int32
  priv merge : HistoryMerge
}

///|
pub fn Engine::branch_pair(
  self : Engine,
  base : Snapshot,
  left_label~ : String = "left",
  right_label~ : String = "right",
) -> BranchPair raise BranchError {
  guard left_label != "" && right_label != "" && left_label != right_label else {
    raise InvalidBranchLabels
  }
  {
    engine: self.fork(),
    base,
    left: { label: left_label, entries: [], },
    right: { label: right_label, entries: [], },
    generation: 0,
    busy: false,
  }
}

///|
fn BranchPair::lane(self : BranchPair, side : Side) -> BranchLane {
  match side {
    Left => self.left
    Right => self.right
  }
}

///|
fn BranchPair::enter(self : BranchPair) -> Unit raise BranchError {
  guard !self.busy else { raise BranchBusy }
  self.busy = true
}

///|
fn BranchPair::next_generation(self : BranchPair) -> Int32 raise BranchError {
  guard self.generation < 2147483647 else { raise BranchRevisionOverflow }
  self.generation + 1
}

///|
pub fn BranchPair::label(self : BranchPair, side : Side) -> String {
  self.lane(side).label
}

///|
pub fn BranchPair::base(self : BranchPair) -> Snapshot {
  self.base
}

///|
pub fn BranchPair::length(self : BranchPair, side : Side) -> Int32 {
  self.lane(side).entries.length()
}

///|
pub fn BranchPair::snapshot(self : BranchPair, side : Side) -> Snapshot {
  match self.lane(side).entries.last() {
    Some(entry) => entry.snapshot
    None => self.base
  }
}

///|
pub fn BranchPair::operations(
  self : BranchPair,
  side : Side,
) -> Array[Operation] {
  self.lane(side).entries.map(entry => entry.operation)
}

///|
pub fn BranchPair::append_all(
  self : BranchPair,
  side : Side,
  operations : Array[Operation],
) -> Snapshot raise BranchError {
  self.enter()
  defer {
    self.busy = false
  }
  let generation = self.next_generation()
  let lane = self.lane(side)
  let pending = lane.entries.copy()
  let mut snapshot = self.snapshot(side)
  guard operations.length() <= 2147483647 - pending.length() else {
    raise BranchRevisionOverflow
  }
  for index, operation in operations {
    snapshot = self.engine.apply_snapshot_verified(snapshot, operation) catch {
      error => raise BranchApply(side, index, error)
    }
    pending.push({ operation, snapshot, })
  }
  let updated = { ..lane, entries: pending, }
  match side {
    Left => self.left = updated
    Right => self.right = updated
  }
  self.generation = generation
  snapshot
}

///|
pub fn BranchPair::append(
  self : BranchPair,
  side : Side,
  operation : Operation,
) -> Snapshot raise BranchError {
  self.append_all(side, [operation])
}

///|
/// Restore a retained branch checkpoint, discarding only in-memory future entries.
pub fn BranchPair::rewind(
  self : BranchPair,
  side : Side,
  count : Int32,
) -> Snapshot raise BranchError {
  self.enter()
  defer {
    self.busy = false
  }
  let lane = self.lane(side)
  guard count >= 0 && count <= lane.entries.length() else {
    raise BranchRange(side, count, lane.entries.length())
  }
  let generation = self.next_generation()
  let updated = { ..lane, entries: lane.entries[:count].to_owned(), }
  match side {
    Left => self.left = updated
    Right => self.right = updated
  }
  self.generation = generation
  self.snapshot(side)
}

///|
pub fn BranchPair::preview(
  self : BranchPair,
  text_encoding~ : TextEncoding? = None,
) -> BranchPreview raise BranchError {
  self.enter()
  defer {
    self.busy = false
  }
  let merge = self.engine.merge_snapshot_histories(
    self.base,
    self.operations(Left),
    self.operations(Right),
    text_encoding~,
  ) catch {
    error => raise BranchHistory(error)
  }
  {
    owner: self,
    generation: self.generation,
    left_count: self.length(Left),
    right_count: self.length(Right),
    merge,
  }
}

///|
pub fn BranchPreview::result(self : BranchPreview) -> Snapshot {
  self.merge.snapshot
}

///|
pub fn BranchPreview::histories(self : BranchPreview) -> TransformedHistories {
  self.merge.histories
}

///|
pub fn BranchPreview::counts(self : BranchPreview) -> (Int32, Int32) {
  (self.left_count, self.right_count)
}

///|
/// Accept only an unchanged preview belonging to this branch pair.
pub fn BranchPair::accept(
  self : BranchPair,
  preview : BranchPreview,
) -> Snapshot raise BranchError {
  self.enter()
  defer {
    self.busy = false
  }
  guard physical_equal(self, preview.owner) &&
    self.generation == preview.generation else {
    raise StaleBranchPreview
  }
  let generation = self.next_generation()
  self.base = preview.merge.snapshot
  self.left = { ..self.left, entries: [], }
  self.right = { ..self.right, entries: [], }
  self.generation = generation
  self.base
}
