///|
#derive(Eq, @debug.Debug)
pub(all) enum CompositionDecision {
  NormalizedComposition
  SequentialFallback
}

///|
pub extend CompositionDecision with Eq::{equal, not_equal}

///|
pub extend CompositionDecision with @debug.Debug::{to_repr}

///|
pub struct VerifiedComposition {
  priv operation : Operation
  priv snapshot : Snapshot
  priv checkpoints : Array[Snapshot]
  priv decision : CompositionDecision
}

///|
pub fn VerifiedComposition::operation(self : VerifiedComposition) -> Operation {
  self.operation
}

///|
pub fn VerifiedComposition::snapshot(self : VerifiedComposition) -> Snapshot {
  self.snapshot
}

///|
pub fn VerifiedComposition::checkpoints(
  self : VerifiedComposition,
) -> Array[Snapshot] {
  self.checkpoints.copy()
}

///|
pub fn VerifiedComposition::decision(
  self : VerifiedComposition,
) -> CompositionDecision {
  self.decision
}

///|
#derive(@debug.Debug)
pub(all) suberror CompositionError {
  SequentialCompositionFailed(Int32, VerificationError)
  CompositionFallbackFailed(VerificationError)
  CompositionFallbackMismatch
}

///|
pub extend CompositionError with @debug.Debug::{to_repr}

///|
/// Compose valid sequential operations while checking their actual result.
/// Floating-point reassociation and custom subtype compaction may change values.
/// In that case, retain the exact original component sequence instead.
pub fn Engine::compose_verified(
  self : Engine,
  snapshot : Snapshot,
  operations : Array[Operation],
) -> VerifiedComposition raise CompositionError {
  let mut result = snapshot
  let checkpoints = [snapshot]
  let components = []
  for index, operation in operations {
    result = self.apply_snapshot_verified(result, operation) catch {
      error => raise SequentialCompositionFailed(index, error)
    }
    checkpoints.push(result)
    components.append(operation.components)
  }
  let candidate = Some(self.compose_all(operations)) catch { _ => None }
  if candidate is Some(operation) {
    let applied = Some(self.apply_snapshot_verified(snapshot, operation)) catch {
      _ => None
    }
    if applied is Some(applied) && applied.equivalent(result) {
      return {
        operation,
        snapshot: result,
        checkpoints,
        decision: NormalizedComposition,
      }
    }
  }
  let operation = Operation::{ components, }
  let applied = self.apply_snapshot_verified(snapshot, operation) catch {
    error => raise CompositionFallbackFailed(error)
  }
  guard applied.equivalent(result) else { raise CompositionFallbackMismatch }
  { operation, snapshot: result, checkpoints, decision: SequentialFallback, }
}

///|
/// Preserve transaction boundaries while composing each bounded group exactly.
pub fn Engine::compose_verified_groups(
  self : Engine,
  snapshot : Snapshot,
  groups : Array[Array[Operation]],
) -> Array[VerifiedComposition] raise CompositionError {
  let results = []
  let mut current = snapshot
  for group in groups {
    let composed = self.compose_verified(current, group)
    current = composed.snapshot
    results.push(composed)
  }
  results
}
