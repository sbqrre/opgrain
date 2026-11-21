///|
#derive(@debug.Debug)
pub(all) enum HistoryPhase {
  Original
  Transformed
}

///|
pub extend HistoryPhase with @debug.Debug::{to_repr}

///|
#derive(@debug.Debug)
pub(all) suberror HistoryError {
  InvalidHistorySnapshot(OpError)
  HistoryBusy
  RevisionOverflow
  HistoryEncodingFailed(Side, Int32, OpError)
  HistoryTransformFailed(Int32, Int32, OpError)
  HistoryApplyFailed(HistoryPhase, Side, Int32, VerificationError)
  DivergentHistory(Json?, Json?)
  InvalidRevisionRange(Int32, Int32, Int32)
  HistoryInvertFailed(Int32, OpError)
  HistoryUndoFailed(Int32, VerificationError)
  HistoryUndoMismatch(Json?, Json?)
}

///|
pub extend HistoryError with @debug.Debug::{to_repr}

///|
/// Operations retain their branch order and original batch boundaries.
pub struct TransformedHistories {
  priv left_after_right : Array[Operation]
  priv right_after_left : Array[Operation]
}

///|
pub fn TransformedHistories::left_after_right(
  self : TransformedHistories,
) -> Array[Operation] {
  self.left_after_right.copy()
}

///|
pub fn TransformedHistories::right_after_left(
  self : TransformedHistories,
) -> Array[Operation] {
  self.right_after_left.copy()
}

///|
/// Cross two sequential histories based on the same starting revision.
/// Left keeps its normal JSON0 tie-break priority at each crossing.
pub fn Engine::transform_histories(
  self : Engine,
  left : Array[Operation],
  right : Array[Operation],
) -> TransformedHistories raise HistoryError {
  let left_after_right = []
  let right_after_left = right.copy()
  for left_index, operation in left {
    let mut across = operation
    for right_index in 0..<right_after_left.length() {
      let other = right_after_left[right_index]
      guard across.length() != 0 else { break }
      if other.length() == 0 {
        continue
      }
      let (next_left, next_right) = self.transform_x(across, other) catch {
        error => raise HistoryTransformFailed(left_index, right_index, error)
      }
      across = next_left
      right_after_left[right_index] = next_right
    }
    left_after_right.push(across)
  }
  { left_after_right, right_after_left, }
}

///|
pub struct HistoryMerge {
  priv histories : TransformedHistories
  priv snapshot : Snapshot
}

///|
pub fn HistoryMerge::histories(self : HistoryMerge) -> TransformedHistories {
  self.histories
}

///|
pub fn HistoryMerge::snapshot(self : HistoryMerge) -> Json? {
  self.snapshot.to_json()
}

///|
fn Engine::prepare_history(
  self : Engine,
  operations : Array[Operation],
  side : Side,
  encoding : TextEncoding?,
) -> Array[Operation] raise HistoryError {
  guard encoding is Some(encoding) else { return operations }
  let output = []
  for index, operation in operations {
    let converted = self.reencode_text(operation, encoding) catch {
      error => raise HistoryEncodingFailed(side, index, error)
    }
    output.push(converted)
  }
  output
}

///|
fn Engine::replay_history(
  self : Engine,
  snapshot : Snapshot,
  operations : Array[Operation],
  phase : HistoryPhase,
  side : Side,
) -> Snapshot raise HistoryError {
  let mut updated = snapshot
  for index, operation in operations {
    updated = self.apply_snapshot_verified(updated, operation) catch {
      error => raise HistoryApplyFailed(phase, side, index, error)
    }
  }
  updated
}

///|
/// Validate each path through the merge and return only a converged snapshot.
pub fn Engine::merge_snapshot_histories(
  self : Engine,
  base : Snapshot,
  left : Array[Operation],
  right : Array[Operation],
  text_encoding~ : TextEncoding? = None,
) -> HistoryMerge raise HistoryError {
  let left = self.prepare_history(left, Left, text_encoding)
  let right = self.prepare_history(right, Right, text_encoding)
  let left_snapshot = self.replay_history(base, left, Original, Left)
  let right_snapshot = self.replay_history(base, right, Original, Right)
  let histories = self.transform_histories(left, right)
  let left_first = self.replay_history(
    left_snapshot,
    histories.right_after_left,
    Transformed,
    Right,
  )
  let right_first = self.replay_history(
    right_snapshot,
    histories.left_after_right,
    Transformed,
    Left,
  )
  guard left_first.value == right_first.value else {
    raise DivergentHistory(left_first.to_json(), right_first.to_json())
  }
  { histories, snapshot: left_first, }
}

///|
pub fn Engine::merge_histories(
  self : Engine,
  base : Json?,
  left : Array[Operation],
  right : Array[Operation],
  text_encoding~ : TextEncoding? = None,
) -> HistoryMerge raise HistoryError {
  let snapshot = Snapshot::new(base) catch {
    error => raise InvalidHistorySnapshot(error)
  }
  self.merge_snapshot_histories(snapshot, left, right, text_encoding~)
}

///|
pub fn HistoryMerge::snapshot_handle(self : HistoryMerge) -> Snapshot {
  self.snapshot
}
