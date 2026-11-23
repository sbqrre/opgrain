///|
pub(all) struct MergeLimits {
  max_branches : Int32
  max_components : Int64
  max_batch_crossings : Int64
}

///|
pub fn MergeLimits::default() -> MergeLimits {
  { max_branches: 64, max_components: 1000000L, max_batch_crossings: 1000000L, }
}

///|
#derive(@debug.Debug)
pub(all) suberror MultiMergeError {
  InvalidMergeLimits
  MergeBudget(String, Int64, Int64)
  BranchMergeFailed(Int32, HistoryError)
}

///|
pub extend MultiMergeError with @debug.Debug::{to_repr}

///|
pub struct MergeContribution {
  priv branch : Int32
  priv original : Array[Operation]
  priv transformed : Array[Operation]
  priv before : Snapshot
  priv after : Snapshot
}

///|
pub fn MergeContribution::branch(self : MergeContribution) -> Int32 {
  self.branch
}

///|
pub fn MergeContribution::original(
  self : MergeContribution,
) -> Array[Operation] {
  self.original.copy()
}

///|
pub fn MergeContribution::transformed(
  self : MergeContribution,
) -> Array[Operation] {
  self.transformed.copy()
}

///|
pub fn MergeContribution::before(self : MergeContribution) -> Snapshot {
  self.before
}

///|
pub fn MergeContribution::after(self : MergeContribution) -> Snapshot {
  self.after
}

///|
pub struct MultiMerge {
  priv base : Snapshot
  priv result : Snapshot
  priv operations : Array[Operation]
  priv contributions : Array[MergeContribution]
  priv crossings : Int64
}

///|
pub fn MultiMerge::base(self : MultiMerge) -> Snapshot {
  self.base
}

///|
pub fn MultiMerge::result(self : MultiMerge) -> Snapshot {
  self.result
}

///|
pub fn MultiMerge::operations(self : MultiMerge) -> Array[Operation] {
  self.operations.copy()
}

///|
pub fn MultiMerge::contributions(self : MultiMerge) -> Array[MergeContribution] {
  self.contributions.copy()
}

///|
pub fn MultiMerge::crossings(self : MultiMerge) -> Int64 {
  self.crossings
}

///|
fn merge_budget(
  name : String,
  actual : Int64,
  maximum : Int64,
) -> Unit raise MultiMergeError {
  guard actual <= maximum else { raise MergeBudget(name, actual, maximum) }
}

///|
/// Merge histories based on the same document in explicit branch priority order.
/// Earlier branches take the left side. This does not assert permutation
/// invariance or add a new conflict-resolution rule to JSON0.
pub fn Engine::merge_many(
  self : Engine,
  base : Snapshot,
  branches : Array[Array[Operation]],
  text_encoding~ : TextEncoding? = None,
  limits~ : MergeLimits = MergeLimits::default(),
) -> MultiMerge raise MultiMergeError {
  guard limits.max_branches >= 0 &&
    limits.max_components >= 0L &&
    limits.max_batch_crossings >= 0L else {
    raise InvalidMergeLimits
  }
  merge_budget(
    "branches",
    branches.length().to_int64(),
    limits.max_branches.to_int64(),
  )
  let mut component_count = 0L
  let mut prior_batches = 0L
  let mut crossings = 0L
  for branch in branches {
    let count = branch.length().to_int64()
    merge_budget(
      "batch crossings",
      count * prior_batches + crossings,
      limits.max_batch_crossings,
    )
    crossings += count * prior_batches
    prior_batches += count
    for operation in branch {
      component_count += operation.length().to_int64()
      merge_budget("components", component_count, limits.max_components)
    }
  }
  let accumulated : Array[Operation] = []
  let contributions = []
  let mut result = base
  for index, branch in branches {
    let merged = self.merge_snapshot_histories(
      base,
      accumulated,
      branch,
      text_encoding~,
    ) catch {
      error => raise BranchMergeFailed(index, error)
    }
    let transformed = merged.histories.right_after_left
    contributions.push({
      branch: index,
      original: branch.copy(),
      transformed: transformed.copy(),
      before: result,
      after: merged.snapshot,
    })
    accumulated.append(transformed)
    result = merged.snapshot
    // Transforms can split components, so enforce the retained output budget too.
    let mut retained = 0L
    for operation in accumulated {
      retained += operation.length().to_int64()
      merge_budget("transformed components", retained, limits.max_components)
    }
  }
  { base, result, operations: accumulated, contributions, crossings, }
}
