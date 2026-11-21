///|
/// An owned JSON value whose containers are only visible through detached reads.
pub struct Snapshot {
  priv value : Json?
}

///|
/// Validate and detach input once. None denotes an absent root.
pub fn Snapshot::new(value : Json?) -> Snapshot raise OpError {
  { value: value.map(copy_checked_json), }
}

///|
pub fn Snapshot::to_json(self : Snapshot) -> Json? {
  self.value.map(copy_json)
}

///|
pub fn Snapshot::read(
  self : Snapshot,
  path : Array[PathSegment],
) -> Json raise OpError {
  copy_json(lookup_value(self.value, path, path.length()))
}

///|
/// Read the root without copying its containers. The result is another opaque snapshot.
pub fn Snapshot::subtree(
  self : Snapshot,
  path : Array[PathSegment],
) -> Snapshot raise OpError {
  { value: Some(lookup_value(self.value, path, path.length())), }
}

///|
/// Apply by copying the edited container and each ancestor. Unedited branches are shared.
pub fn Engine::apply_snapshot(
  self : Engine,
  snapshot : Snapshot,
  operation : Operation,
) -> Snapshot raise OpError {
  let mut value = snapshot.value
  for component in operation.components {
    value = self.apply_component(value, component, persistent=true)
  }
  { value, }
}

///|
/// Verify preimages against the evolving snapshot before applying each component.
pub fn Engine::apply_snapshot_verified(
  self : Engine,
  snapshot : Snapshot,
  operation : Operation,
) -> Snapshot raise VerificationError {
  let mut value = snapshot.value
  for index, component in operation.components {
    value = self.verify_component(value, component, index, persistent=true)
  }
  { value, }
}

///|
/// Validate the whole sequence before returning a new snapshot.
pub fn Engine::apply_snapshot_batches(
  self : Engine,
  snapshot : Snapshot,
  operations : Array[Operation],
) -> Snapshot raise HistoryError {
  let mut updated = snapshot
  for index, operation in operations {
    updated = self.apply_snapshot_verified(updated, operation) catch {
      error => raise HistoryApplyFailed(Original, Left, index, error)
    }
  }
  updated
}
