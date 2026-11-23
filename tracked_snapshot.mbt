///|
pub struct TrackedSnapshot {
  priv snapshot : Snapshot
  priv locations : Array[Location?]
  priv losses : Array[LocationLoss?]
  priv batches : Int32
}

///|
pub fn TrackedSnapshot::snapshot(self : TrackedSnapshot) -> Snapshot {
  self.snapshot
}

///|
pub fn TrackedSnapshot::locations(self : TrackedSnapshot) -> Array[Location?] {
  self.locations.map(location => location.map(Location::detached))
}

///|
pub fn TrackedSnapshot::losses(self : TrackedSnapshot) -> Array[LocationLoss?] {
  self.losses.copy()
}

///|
pub fn TrackedSnapshot::batches(self : TrackedSnapshot) -> Int32 {
  self.batches
}

///|
pub fn Snapshot::track(
  self : Snapshot,
  locations : Array[Location],
) -> TrackedSnapshot raise TrackingError {
  let current = []
  for index, location in locations {
    validate_location(self.value, location) catch {
      error => raise InvalidLocation(index, location.path().copy(), error)
    }
    current.push(Some(location.detached()))
  }
  {
    snapshot: self,
    locations: current,
    losses: Array::make(current.length(), None),
    batches: 0,
  }
}

///|
pub fn Selection::track(
  self : Selection,
) -> TrackedSnapshot raise TrackingError {
  self.snapshot.track(self.paths.map(path => Node(path.segments())))
}

///|
/// Track existing anchors through persistent snapshot updates. Lost anchors
/// remain lost; later inserts at the same path do not resurrect their identity.
pub fn Engine::advance_tracking(
  self : Engine,
  tracked : TrackedSnapshot,
  operations : Array[Operation],
) -> TrackedSnapshot raise TrackingError {
  guard operations.length() <= 2147483647 - tracked.batches else {
    raise TrackingSnapshotFailed(InvalidJson("tracking batch counter overflow"))
  }
  let locations = tracked.locations.copy()
  let losses = tracked.losses.copy()
  let mut snapshot = tracked.snapshot
  for batch, operation in operations {
    for index, component in operation.components {
      let value = self.verify_component(
        snapshot.value,
        component,
        index,
        persistent=true,
      ) catch {
        error => raise TrackingApplyFailed(batch + tracked.batches, error)
      }
      snapshot = { value, }
      let effect = self.location_change(component) catch {
        error =>
          raise TrackingApplyFailed(
            batch + tracked.batches,
            ComponentFailed(index, component.path.copy(), error),
          )
      }
      if effect is NoChange {
        continue
      }
      for anchor, location in locations {
        if location is Some(location) {
          let next = location.after_change(effect)
          if next is None && effect.loss_reason() is Some(reason) {
            losses[anchor] = Some({
              batch: tracked.batches + batch,
              component: index,
              reason,
            })
          }
          locations[anchor] = next
        }
      }
    }
  }
  {
    snapshot,
    locations,
    losses,
    batches: tracked.batches + operations.length(),
  }
}

///|
pub fn Engine::apply_tracked_snapshot(
  self : Engine,
  snapshot : Snapshot,
  operation : Operation,
  locations : Array[Location],
) -> TrackedSnapshot raise TrackingError {
  self.advance_tracking(snapshot.track(locations), [operation])
}

///|
pub fn TrackedSnapshot::alive(self : TrackedSnapshot) -> Int32 {
  self.locations.filter(location => location is Some(_)).length()
}

///|
/// Detached values remain aligned with the original anchor indices.
pub fn TrackedSnapshot::values(
  self : TrackedSnapshot,
) -> Array[Json?] raise OpError {
  self.locations.map(location => {
    match location {
      Some(location) => Some(self.snapshot.read(location.path()))
      None => None
    }
  })
}

///|
pub fn TrackedSnapshot::paths(self : TrackedSnapshot) -> Array[Path?] {
  self.locations.map(location => {
    location.map(location => { segments: location.path().copy(), })
  })
}

///|
pub fn TrackedSnapshot::location(
  self : TrackedSnapshot,
  index : Int32,
) -> Location? raise OpError {
  guard index >= 0 && index < self.locations.length() else {
    raise InvalidJson("anchor index outside tracked set")
  }
  self.locations[index].map(Location::detached)
}

///|
/// Retain an explicit subset of anchor slots, including their original losses.
pub fn TrackedSnapshot::retain(
  self : TrackedSnapshot,
  indices : Array[Int32],
) -> TrackedSnapshot raise OpError {
  let locations = []
  let losses = []
  for index in indices {
    guard index >= 0 && index < self.locations.length() else {
      raise InvalidJson("anchor index outside tracked set")
    }
    locations.push(self.locations[index])
    losses.push(self.losses[index])
  }
  { snapshot: self.snapshot, locations, losses, batches: self.batches, }
}

///|
/// Add anchors at the current revision. Prior anchor identities are preserved.
pub fn TrackedSnapshot::with_anchors(
  self : TrackedSnapshot,
  locations : Array[Location],
) -> TrackedSnapshot raise TrackingError {
  let appended = self.snapshot.track(locations)
  let current = self.locations.copy()
  current.append(appended.locations)
  let losses = self.losses.copy()
  losses.append(appended.losses)
  {
    snapshot: self.snapshot,
    locations: current,
    losses,
    batches: self.batches,
  }
}
